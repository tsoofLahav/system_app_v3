"""Production agent runner — Responses API conversation + tool loop.

Standing instructions come from `agent_configs`. File bodies are never in the
first turn; content is loaded only via tools. Follow-up turns send tool results
only. The OpenAI conversation is deleted when the run ends.
"""

from __future__ import annotations

import json
import logging
from datetime import datetime, timezone
from typing import Any

from models import File, db
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
from areas.production_agent.services.browse_tools import (
    file_allowed,
    find_file,
    find_object,
    list_archived_files,
    list_entities,
)
from areas.production_agent.services.create_file_tool import create_file
from areas.production_agent.services.create_object_tool import create_object
from areas.production_agent.services.views_tool import views_tool
from areas.production_agent.services.connect_tool import connect_tool
from areas.production_agent.services.pending_reviews import upsert_pending_from_proposals
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

# Finding the right topic, opening a file, creating an embed and filling it is
# already six rounds before anything goes wrong. A ceiling that stops the run
# mid-search is worse than a slow run.
MAX_TOOL_ROUNDS = 16

# Re-export for file_versions / tests.
__all__ = ["compute_diff", "run_agent"]


def _open_file(file_id: int, scope: dict) -> dict:
    file = db.session.get(File, file_id)
    if file is None:
        return {"error": "file not found"}
    if not file_allowed(file, scope):
        return {"error": "file out of scope"}
    # Archived files are readable; update_file rejects writes.
    return build_open_file_payload(file)


TOOL_DEFS: list[dict[str, Any]] = [
    {
        "type": "function",
        "name": "list",
        "description": (
            "Browse the live workspace. kind: topics | files | objects. "
            "files are live only (use list_archived for archived files). "
            "files/objects come back grouped under their topic "
            "(topics[].topic = topic name, topics[].topic_type = type name, "
            "topics[].files[]; objects also carry their file name). "
            "Read the topic names and types and pick the topic "
            "that matches the subject of the ask before choosing a file. "
            "topic_id: 0 = all topics; else only that topic."
        ),
        "strict": True,
        "parameters": {
            "type": "object",
            "properties": {
                "kind": {
                    "type": "string",
                    "description": "topics | files | objects",
                },
                "topic_id": {
                    "type": "integer",
                    "description": "0 = all topics; else filter",
                },
            },
            "required": ["kind", "topic_id"],
            "additionalProperties": False,
        },
    },
    {
        "type": "function",
        "name": "list_archived",
        "description": (
            "Browse archived files, grouped under their topic. "
            "Live files are on list kind=files. "
            "topic_id: 0 = all topics; else only that topic. "
            "open_file can still read an archived file by id; writes stay rejected."
        ),
        "strict": True,
        "parameters": {
            "type": "object",
            "properties": {
                "topic_id": {
                    "type": "integer",
                    "description": "0 = all topics; else filter",
                },
            },
            "required": ["topic_id"],
            "additionalProperties": False,
        },
    },
    {
        "type": "function",
        "name": "find_file",
        "description": (
            "Find a file by id, or by name substring (optional topic_id). "
            "Each hit carries its topic name — check it before writing. "
            "file_id: 0 when searching by name. topic_id: 0 = any topic. "
            "name: \"\" when using file_id."
        ),
        "strict": True,
        "parameters": {
            "type": "object",
            "properties": {
                "file_id": {"type": "integer", "description": "0 if using name"},
                "name": {"type": "string", "description": "Substring; \"\" if using file_id"},
                "topic_id": {"type": "integer", "description": "0 = any topic"},
            },
            "required": ["file_id", "name", "topic_id"],
            "additionalProperties": False,
        },
    },
    {
        "type": "function",
        "name": "find_object",
        "description": (
            "Find an object by id, or by type and/or name (optional topic_id). "
            "Each hit carries its file and topic name. "
            "Types: task_list | info | table | graph | image. "
            "object_id: 0 when filtering. Unused strings are \"\". topic_id: 0 = any."
        ),
        "strict": True,
        "parameters": {
            "type": "object",
            "properties": {
                "object_id": {"type": "integer", "description": "0 if filtering"},
                "name": {"type": "string"},
                "type": {
                    "type": "string",
                    "description": "task_list | info | table | graph | image | \"\"",
                },
                "topic_id": {"type": "integer", "description": "0 = any topic"},
            },
            "required": ["object_id", "name", "type", "topic_id"],
            "additionalProperties": False,
        },
    },
    {
        "type": "function",
        "name": "open_file",
        "description": (
            "Open one workspace file (including archived — read-only). "
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
        "name": "create_file",
        "description": (
            "Create a new empty file in a topic. "
            "Returns file_id — then open_file and patch_file / rewrite_file "
            "to fill it. name is required. topic_id must be a real topic id "
            "from list / find_file (never invent one). "
            "The new file is placed first in that topic."
        ),
        "strict": True,
        "parameters": {
            "type": "object",
            "properties": {
                "topic_id": {
                    "type": "integer",
                    "description": "Topic that will own the file",
                },
                "name": {
                    "type": "string",
                    "description": "File name; required, non-empty",
                },
            },
            "required": ["topic_id", "name"],
            "additionalProperties": False,
        },
    },
    {
        "type": "function",
        "name": "create_object",
        "description": (
            "Create a new embed in a file and insert its pointer. "
            "Types: task_list | info | table | graph | image. "
            "Returns object_id — then open_file and patch_file to fill content "
            "(except image: body is the picture to generate; the tool stores "
            "the file — never invent a url). "
            "after_line: 0 = append at end; else insert after that open_file line. "
            "title/body optional seeds (\"\" if unused). "
            "For image, title is the caption and body must describe the picture."
        ),
        "strict": True,
        "parameters": {
            "type": "object",
            "properties": {
                "file_id": {"type": "integer"},
                "type": {
                    "type": "string",
                    "description": "task_list | info | table | graph | image",
                },
                "title": {"type": "string"},
                "body": {"type": "string"},
                "after_line": {
                    "type": "integer",
                    "description": "0 = end of file; else after this agent-text line",
                },
            },
            "required": ["file_id", "type", "title", "body", "after_line"],
            "additionalProperties": False,
        },
    },
    {
        "type": "function",
        "name": "views",
        "description": (
            "List workspace views and their sections, or assign a task to a view. "
            "A task belongs to at most one view; assign replaces any previous one. "
            "action=list: no other fields needed (pass 0 / \"\"). "
            "action=assign: identify the task by task_id, or by object_id "
            "(the [TASK_LIST] id from open_file) plus title. "
            "view_id 0 removes the task from every view. "
            "section_name \"\" is Uncategorized (not a named section). "
            "Call list first when choosing a view or section yourself."
        ),
        "strict": True,
        "parameters": {
            "type": "object",
            "properties": {
                "action": {
                    "type": "string",
                    "description": "list | assign",
                },
                "task_id": {
                    "type": "integer",
                    "description": "Task id; 0 if using object_id + title",
                },
                "object_id": {
                    "type": "integer",
                    "description": "[TASK_LIST] object id; 0 if using task_id",
                },
                "title": {
                    "type": "string",
                    "description": "Task title when using object_id; else \"\"",
                },
                "view_id": {
                    "type": "integer",
                    "description": "View id; 0 = list unused, or remove from views",
                },
                "section_name": {
                    "type": "string",
                    "description": "Named section from list; \"\" = Uncategorized",
                },
            },
            "required": [
                "action",
                "task_id",
                "object_id",
                "title",
                "view_id",
                "section_name",
            ],
            "additionalProperties": False,
        },
    },
    {
        "type": "function",
        "name": "connect",
        "description": (
            "Connect an info object to text or to another info. "
            "action=related: info↔info map edge. source_object_id and "
            "target_object_id are both info objects. "
            "action=description: underline text on a host and point it at "
            "an info (target_object_id). Host is source_task_id (a task title) "
            "or source_object_id (info / table / task-list title). "
            "text is the exact span to find. segment_id is optional when the "
            "host has one field, required when the same text appears in more "
            "than one table cell. Unused fields are 0 / \"\". "
            "Description and related stay separate — do not add a map edge "
            "just because the span is inside an info."
        ),
        "strict": True,
        "parameters": {
            "type": "object",
            "properties": {
                "action": {
                    "type": "string",
                    "description": "related | description",
                },
                "source_object_id": {
                    "type": "integer",
                    "description": "Host or related source object; 0 if using source_task_id",
                },
                "source_task_id": {
                    "type": "integer",
                    "description": "Task id for a title span; 0 otherwise",
                },
                "target_object_id": {
                    "type": "integer",
                    "description": "Info object to connect to",
                },
                "text": {
                    "type": "string",
                    "description": "Exact span to underline; \"\" for related",
                },
                "segment_id": {
                    "type": "string",
                    "description": "Optional host segment (e.g. table cell); else \"\"",
                },
            },
            "required": [
                "action",
                "source_object_id",
                "source_task_id",
                "target_object_id",
                "text",
                "segment_id",
            ],
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
            "Partial edits using open_file document_lines (1-based). Each edit "
            "has op: add | remove | replace. "
            "replace: change an existing line/range (rephrase, sharpen, enrich). "
            "add: insert new data or a new point after line (line=0 = start). "
            "remove: delete an unneeded, unwanted, or repeating line "
            "(end_line=0, text=\"\"). "
            "Inside a fence/list: edit content lines; preserve markers and id=\"…\". "
            "Table cells use \\t between columns."
        ),
        "strict": True,
        "parameters": {
            "type": "object",
            "properties": {
                "file_id": {"type": "integer"},
                "edits": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "op": {
                                "type": "string",
                                "description": "add | remove | replace",
                            },
                            "line": {
                                "type": "integer",
                                "description": (
                                    "add: after this line (0=start); "
                                    "remove/replace: first line"
                                ),
                            },
                            "end_line": {
                                "type": "integer",
                                "description": "replace: last line inclusive; else 0",
                            },
                            "text": {
                                "type": "string",
                                "description": "add/replace content; remove: \"\"",
                            },
                        },
                        "required": ["op", "line", "end_line", "text"],
                        "additionalProperties": False,
                    },
                },
            },
            "required": ["file_id", "edits"],
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
]


def _optional_id(value: Any) -> int | None:
    try:
        n = int(value)
    except (TypeError, ValueError):
        return None
    return None if n == 0 else n


def _dispatch_tool(name: str, args: dict, scope: dict, apply_mode: str) -> Any:
    workspace_id = int(scope.get("workspace_id") or 0)
    if name == "list":
        if not workspace_id:
            return {"error": "workspace_id missing from run"}
        topic_id = _optional_id(args.get("topic_id"))
        return list_entities(
            workspace_id,
            kind=str(args.get("kind") or ""),
            topic_id=topic_id,
        )
    if name == "list_archived":
        if not workspace_id:
            return {"error": "workspace_id missing from run"}
        topic_id = _optional_id(args.get("topic_id"))
        return list_archived_files(workspace_id, topic_id=topic_id)
    if name == "find_file":
        if not workspace_id:
            return {"error": "workspace_id missing from run"}
        return find_file(
            workspace_id,
            file_id=_optional_id(args.get("file_id")),
            name=str(args.get("name") or "") or None,
            topic_id=_optional_id(args.get("topic_id")),
        )
    if name == "find_object":
        if not workspace_id:
            return {"error": "workspace_id missing from run"}
        return find_object(
            workspace_id,
            object_id=_optional_id(args.get("object_id")),
            name=str(args.get("name") or "") or None,
            type_=str(args.get("type") or "") or None,
            topic_id=_optional_id(args.get("topic_id")),
        )
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
    if name == "create_file":
        try:
            topic_id = int(args["topic_id"])
        except (KeyError, TypeError, ValueError):
            return {"error": "topic_id required", "tool": "create_file"}
        write_mode = resolve_write_mode("create_file", apply_mode)
        return create_file(
            topic_id=topic_id,
            name=str(args.get("name") or ""),
            scope=scope,
            write_mode=write_mode,
        )
    if name == "create_object":
        try:
            file_id = int(args["file_id"])
        except (KeyError, TypeError, ValueError):
            return {"error": "file_id required", "tool": "create_object"}
        write_mode = resolve_write_mode("create_object", apply_mode)
        after = _optional_id(args.get("after_line"))
        return create_object(
            file_id=file_id,
            type_=str(args.get("type") or ""),
            scope=scope,
            write_mode=write_mode,
            title=str(args.get("title") or ""),
            body=str(args.get("body") or ""),
            after_line=after,
        )
    if name == "views":
        if not workspace_id:
            return {"error": "workspace_id missing from run", "tool": "views"}
        write_mode = resolve_write_mode("views", apply_mode)
        return views_tool(
            workspace_id=workspace_id,
            action=str(args.get("action") or ""),
            write_mode=write_mode,
            task_id=_optional_id(args.get("task_id")),
            object_id=_optional_id(args.get("object_id")),
            title=str(args.get("title") or ""),
            view_id=_optional_id(args.get("view_id")),
            section_name=str(args.get("section_name") or ""),
        )
    if name == "connect":
        if not workspace_id:
            return {"error": "workspace_id missing from run", "tool": "connect"}
        write_mode = resolve_write_mode("connect", apply_mode)
        return connect_tool(
            workspace_id=workspace_id,
            action=str(args.get("action") or ""),
            write_mode=write_mode,
            source_object_id=_optional_id(args.get("source_object_id")),
            source_task_id=_optional_id(args.get("source_task_id")),
            target_object_id=_optional_id(args.get("target_object_id")),
            text=str(args.get("text") or ""),
            segment_id=str(args.get("segment_id") or ""),
        )
    if name in WRITE_TOOL_NAMES or name == "update_file":
        # update_file kept as alias → patch_file for older prompts.
        tool_name = "patch_file" if name == "update_file" else name
        if tool_name == "create_object":
            return {"error": "use create_object handler", "tool": "create_object"}
        try:
            file_id = int(args["file_id"])
        except (KeyError, TypeError, ValueError):
            return {"error": "file_id required"}
        write_mode = resolve_write_mode(tool_name, apply_mode)
        if tool_name == "patch_file":
            edits = args.get("edits")
            if isinstance(edits, list):
                return patch_file(
                    file_id,
                    edits,
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
                "error": "edits array required (op, line, end_line, text)",
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


def _with_time_hints(hints: dict[str, Any]) -> dict[str, Any]:
    """The model has no clock, so a dated line is invented unless we say the date.

    The client sends the user's local day; automations have no client, so fall
    back to server UTC.
    """
    if hints.get("today"):
        return hints
    now = datetime.now(timezone.utc)
    return {
        **hints,
        "today": now.strftime("%Y-%m-%d"),
        "weekday": now.strftime("%A"),
        "now": now.strftime("%Y-%m-%dT%H:%M:%S+00:00"),
    }


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
    scope = dict(scope or {})
    scope["workspace_id"] = int(workspace_id)
    apply_mode = (apply_mode or DEFAULT_MANUAL_APPLY_MODE).strip()
    # `context` is legacy; merge into hints (hints win on key clash).
    merged_hints = {**(context or {}), **(hints or {})}
    hints = _with_time_hints(_clean_hints(merged_hints))

    instructions = system_prompt_for_workspace(workspace_id)
    model = _model_for_workspace(workspace_id)
    # First message still shows topic/file context from the client; tools use workspace.
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
                        or result_tool == "views"
                        or result_tool == "connect"
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

    pending_ids: list[int] = []
    if apply_mode == "review" and proposed_changes:
        try:
            import uuid

            run_key = conversation_id or str(uuid.uuid4())
            pending_ids = upsert_pending_from_proposals(
                workspace_id=int(workspace_id),
                run_key=str(run_key),
                proposed_changes=[
                    c for c in proposed_changes if isinstance(c, dict)
                ],
            )
            if pending_ids:
                db.session.commit()
        except Exception:
            logger.exception("failed to persist pending reviews")
            db.session.rollback()
            pending_ids = []

    print(
        f"[agent-run] tools={[t.get('name') for t in tool_trace]} "
        f"proposed={len(proposed_changes)} applied={applied} "
        f"pending={len(pending_ids)} "
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
        "pending_review_ids": pending_ids,
        "has_pending_review": bool(pending_ids),
    }
