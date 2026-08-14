"""Production agent runner — Responses API conversation + tool loop.

Standing instructions come from `agent_configs`. File bodies are never in the
first turn; content is loaded only via tools. Follow-up turns send tool results
only. The OpenAI conversation is deleted when the run ends.
"""

from __future__ import annotations

import json
import logging
from typing import Any

from models import File, ObjectEmbed, Task, db
from areas.files.services.document_agent_text import (
    document_to_agent_text,
    load_objects_by_id,
)
from areas.production_agent.services.prompt import (
    ensure_agent_config,
    load_reference_section,
    system_prompt_for_workspace,
)
from areas.production_agent.services.openai_service import (
    create_conversation,
    create_response,
    delete_conversation,
    function_calls_from_response,
    output_text_from_response,
)
from areas.production_agent.services.open_file_tool import build_open_file_payload
from areas.production_agent.services.write_tools import (
    WRITE_TOOL_NAMES,
    apply_document_text,
    compute_diff,
    patch_file,
    resolve_write_mode,
)
from config import OPENAI_MODEL
from shared.run_config import DEFAULT_MANUAL_APPLY_MODE

logger = logging.getLogger(__name__)

MAX_TOOL_ROUNDS = 8

# Re-export for file_versions / tests.
__all__ = ["compute_diff", "run_agent"]


def _scope_file_ids(scope: dict) -> list[int]:
    return [int(x) for x in (scope.get("file_ids") or [])]


def _scope_topic_ids(scope: dict) -> list[int]:
    return [int(x) for x in (scope.get("topic_ids") or [])]


def _file_in_scope(file: File, scope: dict) -> bool:
    file_ids = _scope_file_ids(scope)
    topic_ids = _scope_topic_ids(scope)
    if file_ids:
        return file.id in file_ids
    if topic_ids:
        return file.topic_id in topic_ids
    return False


def _scoped_files_query(scope: dict, *, include_archived: bool = False):
    q = File.query
    if not include_archived:
        q = q.filter(File.archived_at.is_(None))
    file_ids = _scope_file_ids(scope)
    topic_ids = _scope_topic_ids(scope)
    if file_ids:
        return q.filter(File.id.in_(file_ids))
    if topic_ids:
        return q.filter(File.topic_id.in_(topic_ids))
    return q.filter(False)


def _search_files(scope: dict, query: str) -> list[dict]:
    # Include archived so the agent can find them when needed; writes stay blocked.
    rows = _scoped_files_query(scope, include_archived=True).all()
    query_lower = (query or "").lower()
    hits: list[dict] = []
    for f in rows:
        objects_by_id = load_objects_by_id(f.id)
        plain = document_to_agent_text(f.document_json or "", objects_by_id=objects_by_id)
        if query_lower in (f.name or "").lower() or query_lower in plain.lower():
            hits.append(
                {
                    "id": f.id,
                    "name": f.name,
                    "topic_id": f.topic_id,
                    "archived": f.archived_at is not None,
                    "snippet": plain[:240],
                }
            )
    return hits


def _open_file(file_id: int, scope: dict) -> dict:
    file = db.session.get(File, file_id)
    if file is None:
        return {"error": "file not found"}
    if not _file_in_scope(file, scope):
        return {"error": "file out of scope"}
    # Archived files are readable; update_file rejects writes.
    return build_open_file_payload(file)


def _search_tasks(scope: dict, query: str) -> list[dict]:
    query_lower = (query or "").lower()
    file_rows = _scoped_files_query(scope).all()
    file_ids = {f.id for f in file_rows}
    if not file_ids:
        return []
    embeds = ObjectEmbed.query.filter(
        ObjectEmbed.file_id.in_(file_ids),
        ObjectEmbed.type == "task_list",
    ).all()
    list_ids = [e.task_list_id for e in embeds if e.task_list_id is not None]
    if not list_ids:
        return []
    tasks = Task.query.filter(
        Task.archived_at.is_(None),
        Task.task_list_id.in_(list_ids),
    ).all()
    return [
        t.to_dict()
        for t in tasks
        if query_lower in (t.title or "").lower()
    ]


TOOL_DEFS: list[dict[str, Any]] = [
    {
        "type": "function",
        "name": "search",
        "description": "Search file names and agent text within the hard scope allow-list.",
        "strict": True,
        "parameters": {
            "type": "object",
            "properties": {"query": {"type": "string"}},
            "required": ["query"],
            "additionalProperties": False,
        },
    },
    {
        "type": "function",
        "name": "open_file",
        "description": (
            "Open one in-scope file (including archived — read-only). "
            "Returns document_plain (agent text with fenced embeds) and "
            "object_extras when useful (info title + Links: id/type/title). "
            "Never invent file or object ids."
        ),
        "strict": True,
        "parameters": {
            "type": "object",
            "properties": {"file_id": {"type": "integer"}},
            "required": ["file_id"],
            "additionalProperties": False,
        },
    },
    {
        "type": "function",
        "name": "reference",
        "description": (
            "Load format or tool-usage examples. Call when unsure how agent text "
            "or a write tool looks. section: agent_text | tools | all."
        ),
        "strict": True,
        "parameters": {
            "type": "object",
            "properties": {
                "section": {
                    "type": "string",
                    "description": "agent_text | tools | all",
                },
            },
            "required": ["section"],
            "additionalProperties": False,
        },
    },
    {
        "type": "function",
        "name": "patch_file",
        "description": (
            "Partial edits in a file: change, delete, or add lines (including "
            "inside [TABLE]/[INFO]/[TASK_LIST] fences). Send exact replacements: "
            "old_text must match open_file uniquely; new_text is that span changed "
            "or extended with new line(s). Text outside those spans is left "
            "unchanged — including blank lines. Do not append a change-log. "
            "Preserve every embed id=\"…\"."
        ),
        "strict": True,
        "parameters": {
            "type": "object",
            "properties": {
                "file_id": {"type": "integer"},
                "replacements": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "old_text": {"type": "string"},
                            "new_text": {"type": "string"},
                        },
                        "required": ["old_text", "new_text"],
                        "additionalProperties": False,
                    },
                },
            },
            "required": ["file_id", "replacements"],
            "additionalProperties": False,
        },
    },
    {
        "type": "function",
        "name": "rewrite_file",
        "description": (
            "Replace an entire file with new agent text when the user asked for a "
            "true whole-file rewrite. Preserve embed object_ids that must survive. "
            "For any partial edit (add/change/delete lines) use patch_file."
        ),
        "strict": True,
        "parameters": {
            "type": "object",
            "properties": {
                "file_id": {"type": "integer"},
                "document_text": {"type": "string"},
            },
            "required": ["file_id", "document_text"],
            "additionalProperties": False,
        },
    },
    {
        "type": "function",
        "name": "search_tasks",
        "description": "Search task titles within scoped files.",
        "strict": True,
        "parameters": {
            "type": "object",
            "properties": {"query": {"type": "string"}},
            "required": ["query"],
            "additionalProperties": False,
        },
    },
]


def _dispatch_tool(name: str, args: dict, scope: dict, apply_mode: str) -> Any:
    if name == "search":
        return _search_files(scope, args.get("query", ""))
    if name == "open_file":
        try:
            file_id = int(args["file_id"])
        except (KeyError, TypeError, ValueError):
            return {"error": "file_id required"}
        return _open_file(file_id, scope)
    if name == "reference":
        return {
            "section": str(args.get("section") or "all"),
            "content": load_reference_section(str(args.get("section") or "all")),
        }
    if name in WRITE_TOOL_NAMES or name == "update_file":
        # update_file kept as alias → patch_file for older prompts.
        tool_name = "patch_file" if name == "update_file" else name
        try:
            file_id = int(args["file_id"])
        except (KeyError, TypeError, ValueError):
            return {"error": "file_id required"}
        write_mode = resolve_write_mode(tool_name, apply_mode)
        if tool_name == "patch_file":
            replacements = args.get("replacements")
            if isinstance(replacements, list):
                return patch_file(
                    file_id,
                    replacements,
                    scope=scope,
                    write_mode=write_mode,
                )
            # Legacy update_file / old patch shape: full document_text.
            document_text = args.get("document_text")
            if document_text is None:
                document_text = args.get("body", "")
            if document_text is not None and str(document_text) != "":
                return apply_document_text(
                    file_id,
                    str(document_text),
                    scope=scope,
                    write_mode=write_mode,
                    tool_name="patch_file",
                )
            return {
                "error": "replacements array required (old_text → new_text)",
                "tool": "patch_file",
            }
        document_text = args.get("document_text")
        if document_text is None:
            document_text = args.get("body", "")
        return apply_document_text(
            file_id,
            str(document_text or ""),
            scope=scope,
            write_mode=write_mode,
            tool_name=tool_name,
        )
    if name == "search_tasks":
        return _search_tasks(scope, args.get("query", ""))
    return {"error": f"unknown tool {name}"}


def _clean_hints(hints: dict | None) -> dict[str, Any]:
    if not hints:
        return {}
    cleaned: dict[str, Any] = {}
    for key, value in hints.items():
        if value is None or value == "":
            continue
        cleaned[str(key)] = value
    return cleaned


def _first_turn_input(*, prompt: str, scope: dict, hints: dict) -> str:
    """Prompt + scope (+ tiny hints). Never file bodies."""
    payload: dict[str, Any] = {
        "prompt": prompt,
        "scope": scope,
    }
    if hints:
        payload["hints"] = hints
    return json.dumps(payload, ensure_ascii=False)


def _model_for_workspace(workspace_id: int) -> str:
    config = ensure_agent_config(workspace_id)
    model = (config.model or "").strip()
    return model or OPENAI_MODEL


def run_agent(
    *,
    prompt: str,
    workspace_id: int,
    scope: dict | None,
    apply_mode: str | None = None,
    context: dict | None = None,
    hints: dict | None = None,
) -> dict:
    scope = scope or {}
    apply_mode = (apply_mode or DEFAULT_MANUAL_APPLY_MODE).strip()
    # `context` is legacy; merge into hints (hints win on key clash).
    merged_hints = {**(context or {}), **(hints or {})}
    hints = _clean_hints(merged_hints)

    if not _scope_file_ids(scope) and not _scope_topic_ids(scope):
        return {
            "status": "error",
            "error": "scope is required (topic_ids and/or file_ids)",
            "messages": [],
            "proposed_changes": [],
            "applied": False,
        }

    instructions = system_prompt_for_workspace(workspace_id)
    model = _model_for_workspace(workspace_id)
    first_input = _first_turn_input(prompt=prompt, scope=scope, hints=hints)

    conversation_id: str | None = None
    tool_trace: list[dict] = []
    proposed_changes: list[dict] = []
    final_summary = ""
    messages: list[dict] = [
        {"role": "system", "content": instructions},
        {"role": "user", "content": first_input},
    ]

    try:
        conversation_id = create_conversation(
            metadata={
                "workspace_id": str(workspace_id),
                "apply_mode": apply_mode,
            }
        )
        logger.info(
            "agent run start workspace=%s conversation=%s scope=%s hints=%s",
            workspace_id,
            conversation_id,
            scope,
            list(hints.keys()),
        )

        response = create_response(
            model=model,
            conversation_id=conversation_id,
            instructions=instructions,
            tools=TOOL_DEFS,
            input=first_input,
        )

        for _ in range(MAX_TOOL_ROUNDS):
            calls = function_calls_from_response(response)
            if not calls:
                final_summary = output_text_from_response(response) or "Done"
                break

            tool_outputs: list[dict[str, Any]] = []
            for call in calls:
                name = call.get("name") or ""
                args = call.get("arguments") or {}
                call_id = call.get("call_id")
                result = _dispatch_tool(name, args, scope, apply_mode)
                tool_trace.append(
                    {"name": name, "arguments": args, "result": result}
                )
                result_tool = (
                    result.get("tool")
                    if isinstance(result, dict)
                    else None
                ) or name
                if (
                    isinstance(result, dict)
                    and (
                        result_tool in WRITE_TOOL_NAMES
                        or name in WRITE_TOOL_NAMES
                        or name == "update_file"
                    )
                    and (result.get("review") or result.get("applied"))
                ):
                    proposed_changes.append(result)
                tool_outputs.append(
                    {
                        "type": "function_call_output",
                        "call_id": call_id,
                        "output": json.dumps(result, ensure_ascii=False, default=str),
                    }
                )

            # Follow-up: tool results only (conversation holds prior turns).
            response = create_response(
                model=model,
                conversation_id=conversation_id,
                instructions=instructions,
                tools=TOOL_DEFS,
                input=tool_outputs,
            )
        else:
            final_summary = output_text_from_response(response) or "Stopped after tool round limit"

    except RuntimeError as error:
        return {
            "status": "error",
            "error": str(error),
            "conversation_id": conversation_id,
            "messages": messages,
            "tool_trace": tool_trace,
            "proposed_changes": proposed_changes,
            "applied": False,
        }
    except Exception as error:
        logger.exception("agent run failed")
        return {
            "status": "error",
            "error": str(error),
            "conversation_id": conversation_id,
            "messages": messages,
            "tool_trace": tool_trace,
            "proposed_changes": proposed_changes,
            "applied": False,
        }
    finally:
        if conversation_id:
            delete_conversation(conversation_id)
            logger.info("agent run end conversation=%s deleted", conversation_id)

    applied = any(
        isinstance(c, dict) and c.get("applied") for c in proposed_changes
    )
    # Commit if any write tool applied; otherwise roll back (review/notify paths).
    if applied:
        db.session.commit()
    else:
        db.session.rollback()

    print(
        f"[agent-run] tools={[t.get('name') for t in tool_trace]} "
        f"proposed={len(proposed_changes)} applied={applied} "
        f"summary_len={len(final_summary)}",
        flush=True,
    )

    return {
        "status": "ok",
        "conversation_id": conversation_id,
        "messages": messages + [{"role": "tools", "content": tool_trace}],
        "tool_trace": tool_trace,
        "summary": final_summary,
        "proposed_changes": proposed_changes,
        "applied": applied,
        "apply_mode": apply_mode,
    }
