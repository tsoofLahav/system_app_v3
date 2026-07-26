from __future__ import annotations

import difflib
import json
from typing import Any

from models import File, ObjectEmbed, Task, Topic, db
from services.document_body import document_plain_text
from services.file_versions import save_file_version
from services.openai_service import chat_json


def compute_diff(old_body: str, new_body: str) -> dict:
    old_plain = document_plain_text(old_body)
    new_plain = document_plain_text(new_body)
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
        "old_body": old_body or "",
        "new_body": new_body or "",
    }


def _search_files(scope: dict, query: str) -> list[dict]:
    q = File.query.filter(File.archived_at.is_(None))
    file_ids = scope.get("file_ids") or []
    topic_ids = scope.get("topic_ids") or []
    if file_ids:
        q = q.filter(File.id.in_(file_ids))
    elif topic_ids:
        q = q.filter(File.topic_id.in_(topic_ids))
    rows = q.all()
    query_lower = query.lower()
    return [
        f.to_dict(include_body=False)
        for f in rows
        if query_lower in (f.name or "").lower()
        or query_lower in document_plain_text(f.body or "").lower()
    ]


def _open_file(file_id: int) -> dict | None:
    file = db.session.get(File, file_id)
    if file is None:
        return None
    data = file.to_dict()
    embeds = ObjectEmbed.query.filter_by(file_id=file_id).all()
    data["objects"] = [e.to_dict() for e in embeds]
    data["body_plain"] = document_plain_text(file.body or "")
    return data


def _update_file(file_id: int, body: str, *, apply_mode: str) -> dict:
    file = db.session.get(File, file_id)
    if file is None:
        return {"error": "file not found"}
    old_body = file.body or ""
    if apply_mode == "notify_only":
        return {"file_id": file_id, "old_body": old_body, "new_body": body, "applied": False}
    if apply_mode == "review":
        return {
            "file_id": file_id,
            "old_body": old_body,
            "new_body": body,
            "applied": False,
            "review": compute_diff(old_body, body),
        }
    save_file_version(file, source="agent")
    file.body = body
    db.session.flush()
    return {"file_id": file_id, "old_body": old_body, "new_body": body, "applied": True}


TOOL_DEFS = [
    {
        "name": "search",
        "description": "Search files by text within scope",
        "parameters": {"query": "string"},
    },
    {
        "name": "open_file",
        "description": "Open a file with body and object ids",
        "parameters": {"file_id": "integer"},
    },
    {
        "name": "update_file",
        "description": "Propose or apply a full file body replacement",
        "parameters": {"file_id": "integer", "body": "string"},
    },
    {
        "name": "search_tasks",
        "description": "Search tasks by title substring",
        "parameters": {"query": "string"},
    },
]


def _dispatch_tool(name: str, args: dict, scope: dict, apply_mode: str) -> Any:
    if name == "search":
        return _search_files(scope, args.get("query", ""))
    if name == "open_file":
        return _open_file(int(args["file_id"]))
    if name == "update_file":
        return _update_file(int(args["file_id"]), args.get("body", ""), apply_mode=apply_mode)
    if name == "search_tasks":
        query = (args.get("query") or "").lower()
        tasks = Task.query.filter(Task.archived_at.is_(None)).all()
        return [t.to_dict() for t in tasks if query in (t.title or "").lower()]
    return {"error": f"unknown tool {name}"}


def run_agent(
    *,
    prompt: str,
    workspace_id: int,
    scope: dict | None,
    apply_mode: str = "review",
    context: dict | None = None,
) -> dict:
    scope = scope or {}
    context = context or {}

    topics = Topic.query.filter_by(workspace_id=workspace_id).all()
    system = (
        "You are a document assistant for system_app. "
        "Use tools to search and open files before editing. "
        "When updating a file, return the FULL new body as a JSON document string "
        "(version + nodes array). Preserve object nodes by object_id. "
        "Use paragraph nodes for text with optional spans for bold/italic. "
        "Respond as JSON: {\"tool_calls\": [{\"name\": \"...\", \"arguments\": {...}}]} "
        "or {\"final\": \"summary text\"} when done."
    )
    user = json.dumps(
        {
            "prompt": prompt,
            "scope": scope,
            "context": context,
            "topics": [t.to_dict() for t in topics],
            "tools": TOOL_DEFS,
        }
    )

    messages: list[dict] = [{"role": "system", "content": system}, {"role": "user", "content": user}]
    tool_results: list[dict] = []
    proposed_changes: list[dict] = []
    final_summary = ""

    for _ in range(6):
        try:
            payload = chat_json(system, user if not tool_results else json.dumps({"tool_results": tool_results, "continue": prompt}))
        except RuntimeError as error:
            return {
                "status": "error",
                "error": str(error),
                "messages": messages,
                "proposed_changes": proposed_changes,
                "applied": False,
            }

        if "final" in payload:
            final_summary = payload["final"]
            break

        calls = payload.get("tool_calls") or []
        if not calls:
            final_summary = payload.get("summary") or "Done"
            break

        for call in calls:
            name = call.get("name")
            args = call.get("arguments") or {}
            result = _dispatch_tool(name, args, scope, apply_mode)
            tool_results.append({"name": name, "arguments": args, "result": result})
            if name == "update_file" and isinstance(result, dict) and result.get("review"):
                proposed_changes.append(result)

    applied = any(c.get("applied") for c in proposed_changes if isinstance(c, dict))
    if apply_mode == "direct_apply":
        db.session.commit()
    else:
        db.session.rollback()

    return {
        "status": "ok",
        "messages": messages + [{"role": "tools", "content": tool_results}],
        "summary": final_summary,
        "proposed_changes": proposed_changes,
        "applied": applied,
    }
