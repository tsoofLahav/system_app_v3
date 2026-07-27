from __future__ import annotations

import difflib
import json
from typing import Any

from models import File, ObjectEmbed, Task, Topic, db
from areas.files.services.document_agent_text import (
    apply_agent_text_to_file,
    apply_object_updates,
    document_to_agent_text,
    load_objects_by_id,
)
from areas.production_agent.services.prompt import system_prompt_for_workspace
from areas.files.services.file_versions import save_file_version
from areas.production_agent.services.openai_service import chat_json


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
        f.to_dict(include_document=False)
        for f in rows
        if query_lower in (f.name or "").lower()
        or query_lower in document_to_agent_text(f.document_json or "").lower()
    ]


def _open_file(file_id: int) -> dict | None:
    file = db.session.get(File, file_id)
    if file is None:
        return None
    data = file.to_dict()
    objects_by_id = load_objects_by_id(file_id)
    data["objects"] = list(objects_by_id.values())
    data["document_plain"] = document_to_agent_text(
        file.document_json or "",
        objects_by_id=objects_by_id,
    )
    return data


def _known_object_ids(file_id: int) -> set[int]:
    embeds = ObjectEmbed.query.filter_by(file_id=file_id).all()
    return {int(e.id) for e in embeds}


def _update_file(file_id: int, document_text: str, *, apply_mode: str) -> dict:
    file = db.session.get(File, file_id)
    if file is None:
        return {"error": "file not found"}
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


TOOL_DEFS = [
    {
        "name": "search",
        "description": "Search files by text within scope",
        "parameters": {"query": "string"},
    },
    {
        "name": "open_file",
        "description": "Open a file with agent document text and embedded objects",
        "parameters": {"file_id": "integer"},
    },
    {
        "name": "update_file",
        "description": "Propose or apply a full document replacement in agent text format",
        "parameters": {"file_id": "integer", "document_text": "string"},
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
        document_text = args.get("document_text")
        if document_text is None:
            document_text = args.get("body", "")
        return _update_file(int(args["file_id"]), document_text, apply_mode=apply_mode)
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
    system = system_prompt_for_workspace(workspace_id)
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
