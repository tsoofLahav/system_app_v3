"""Production agent runner — Responses API conversation + tool loop.

Standing instructions come from `agent_configs`. File bodies are never in the
first turn; content is loaded only via tools. Follow-up turns send tool results
only. The OpenAI conversation is deleted when the run ends.
"""

from __future__ import annotations

import difflib
import json
import logging
from typing import Any

from models import File, ObjectEmbed, Task, db
from areas.files.services.document_agent_text import (
    apply_agent_text_to_file,
    apply_object_updates,
    document_to_agent_text,
    load_objects_by_id,
)
from areas.production_agent.services.prompt import (
    ensure_agent_config,
    system_prompt_for_workspace,
)
from areas.files.services.file_versions import save_file_version
from areas.production_agent.services.openai_service import (
    create_conversation,
    create_response,
    delete_conversation,
    function_calls_from_response,
    output_text_from_response,
)
from config import OPENAI_MODEL

logger = logging.getLogger(__name__)

MAX_TOOL_ROUNDS = 8


def compute_diff(
    old_document_json: str,
    new_document_json: str,
    *,
    file_id: int | None = None,
    objects_by_id: dict[int, dict[str, Any]] | None = None,
) -> dict:
    if objects_by_id is None and file_id is not None:
        objects_by_id = load_objects_by_id(file_id)
    objects_by_id = objects_by_id or {}
    old_plain = document_to_agent_text(old_document_json, objects_by_id=objects_by_id)
    new_plain = document_to_agent_text(new_document_json, objects_by_id=objects_by_id)
    old_lines = old_plain.splitlines(keepends=True)
    new_lines = new_plain.splitlines(keepends=True)
    hunks = list(
        difflib.unified_diff(
            old_lines,
            new_lines,
            fromfile="before",
            tofile="after",
        )
    )
    return {
        "diff_hunks": "".join(hunks),
        "old_document_text": old_plain,
        "new_document_text": new_plain,
    }


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


def _scoped_files_query(scope: dict):
    q = File.query.filter(File.archived_at.is_(None))
    file_ids = _scope_file_ids(scope)
    topic_ids = _scope_topic_ids(scope)
    if file_ids:
        return q.filter(File.id.in_(file_ids))
    if topic_ids:
        return q.filter(File.topic_id.in_(topic_ids))
    return q.filter(False)


def _search_files(scope: dict, query: str) -> list[dict]:
    rows = _scoped_files_query(scope).all()
    query_lower = (query or "").lower()
    hits: list[dict] = []
    for f in rows:
        objects_by_id = load_objects_by_id(f.id)
        plain = document_to_agent_text(f.document_json or "", objects_by_id=objects_by_id)
        if query_lower in (f.name or "").lower() or query_lower in plain.lower():
            data = f.to_dict(include_document=False)
            data["snippet"] = plain[:240]
            hits.append(data)
    return hits


def _open_file(file_id: int, scope: dict) -> dict:
    file = db.session.get(File, file_id)
    if file is None:
        return {"error": "file not found"}
    if not _file_in_scope(file, scope):
        return {"error": "file out of scope"}
    objects_by_id = load_objects_by_id(file_id)
    return {
        "id": file.id,
        "name": file.name,
        "topic_id": file.topic_id,
        "archived": file.archived_at is not None,
        "document_plain": document_to_agent_text(
            file.document_json or "",
            objects_by_id=objects_by_id,
        ),
        # Minimal extras — full object dumps wait for step 2 polish.
        "objects": [
            {
                "id": oid,
                "type": obj.get("type"),
                "title": _object_title(obj),
            }
            for oid, obj in objects_by_id.items()
        ],
    }


def _object_title(obj: dict) -> str | None:
    info = obj.get("information") or {}
    if isinstance(info, dict) and info.get("title"):
        return str(info["title"])
    task_list = obj.get("task_list") or {}
    if isinstance(task_list, dict) and task_list.get("title"):
        return str(task_list["title"])
    payload = obj.get("payload") or {}
    if isinstance(payload, dict):
        for key in ("title", "caption", "name"):
            if payload.get(key):
                return str(payload[key])
    return None


def _known_object_ids(file_id: int) -> set[int]:
    embeds = ObjectEmbed.query.filter_by(file_id=file_id).all()
    return {int(e.id) for e in embeds}


def _update_file(file_id: int, document_text: str, *, scope: dict, apply_mode: str) -> dict:
    file = db.session.get(File, file_id)
    if file is None:
        return {"error": "file not found"}
    if not _file_in_scope(file, scope):
        return {"error": "file out of scope"}
    if file.archived_at is not None:
        return {"error": "archived files are read-only"}

    old_document = file.document_json or ""
    known_ids = _known_object_ids(file_id)
    new_document_json, object_updates, errors = apply_agent_text_to_file(
        file_id,
        old_document,
        document_text,
        known_object_ids=known_ids,
    )
    if errors:
        return {"error": "; ".join(errors)}

    if apply_mode == "notify_only":
        return {
            "file_id": file_id,
            "old_document_json": old_document,
            "new_document_json": new_document_json,
            "document_text": document_text,
            "applied": False,
        }
    if apply_mode == "review":
        return {
            "file_id": file_id,
            "old_document_json": old_document,
            "new_document_json": new_document_json,
            "document_text": document_text,
            "applied": False,
            "review": compute_diff(old_document, new_document_json or "", file_id=file_id),
        }

    save_file_version(file, source="agent")
    file.document_json = new_document_json
    update_errors = apply_object_updates(file_id, object_updates)
    if update_errors:
        return {"error": "; ".join(update_errors)}
    db.session.flush()
    return {
        "file_id": file_id,
        "old_document_json": old_document,
        "new_document_json": new_document_json,
        "document_text": document_text,
        "applied": True,
    }


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
            "Open one in-scope file. Returns agent text (document_plain) plus "
            "minimal object id/title/type extras. Never invent file ids."
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
        "name": "update_file",
        "description": (
            "Propose or apply a full document replacement in agent text format. "
            "Preserve every existing embed object_id; never omit fenced object blocks."
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
    if name == "update_file":
        try:
            file_id = int(args["file_id"])
        except (KeyError, TypeError, ValueError):
            return {"error": "file_id required"}
        document_text = args.get("document_text")
        if document_text is None:
            document_text = args.get("body", "")
        return _update_file(
            file_id,
            document_text,
            scope=scope,
            apply_mode=apply_mode,
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
    apply_mode: str = "review",
    context: dict | None = None,
    hints: dict | None = None,
) -> dict:
    scope = scope or {}
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
                if (
                    name == "update_file"
                    and isinstance(result, dict)
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
    if apply_mode == "direct_apply":
        db.session.commit()
    else:
        db.session.rollback()

    return {
        "status": "ok",
        "conversation_id": conversation_id,
        "messages": messages + [{"role": "tools", "content": tool_trace}],
        "tool_trace": tool_trace,
        "summary": final_summary,
        "proposed_changes": proposed_changes,
        "applied": applied,
    }
