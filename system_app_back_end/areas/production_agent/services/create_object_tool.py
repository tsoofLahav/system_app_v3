"""Agent create_object tool — allocate embed id + insert pointer."""

from __future__ import annotations

from typing import Any

from models import File, db
from areas.files.services.document_agent_text import load_objects_by_id
from areas.objects.services.create_embed import create_embed_in_file
from areas.production_agent.services.browse_tools import (
    block_index_after_agent_line,
    file_allowed,
)
from areas.production_agent.services.write_tools import WriteMode, resolve_write_mode


def create_object(
    *,
    file_id: int,
    type_: str,
    scope: dict,
    write_mode: WriteMode,
    title: str = "",
    body: str = "",
    after_line: int | None = None,
) -> dict[str, Any]:
    file = db.session.get(File, file_id)
    if file is None:
        return {"error": "file not found", "tool": "create_object"}
    if not file_allowed(file, scope):
        return {"error": "file out of scope", "tool": "create_object"}
    if file.archived_at is not None:
        return {"error": "archived files are read-only", "tool": "create_object"}

    block_index: int | None = None
    if after_line is not None:
        objects_by_id = load_objects_by_id(file.id)
        block_index = block_index_after_agent_line(
            file.document_json or "",
            objects_by_id,
            int(after_line),
        )

    try:
        embed = create_embed_in_file(
            file,
            type_=type_,
            title=title or "",
            body=body or "",
            block_index=block_index,
        )
    except ValueError as err:
        return {"error": str(err), "tool": "create_object"}

    result: dict[str, Any] = {
        "tool": "create_object",
        "file_id": file.id,
        "object_id": embed.id,
        "type": type_ if type_ != "graph" else "graph",
        "write_mode": write_mode,
    }
    if write_mode == "notify_only":
        return {**result, "applied": False}
    if write_mode == "review":
        # Still flushed in-session so later open_file/patch see the id; run may roll back.
        return {**result, "applied": False}
    return {**result, "applied": True}


def create_object_write_mode(run_apply_mode: str) -> WriteMode:
    return resolve_write_mode("create_object", run_apply_mode)
