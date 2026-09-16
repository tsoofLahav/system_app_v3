"""Agent archive_file tool — move a file to archive.

Archiving is a file-lifecycle action, not a content edit: review mode exists
to gate proposed *text* changes, not this. It always applies immediately,
even on a review-mode run (only ``notify_only`` — a dry run with no side
effects at all — holds it back).
"""

from __future__ import annotations

from typing import Any

from models import File, db
from areas.files.services import file_ops
from areas.production_agent.services.browse_tools import file_allowed


def archive_file_tool(*, file_id: int | None, scope: dict, write_mode: str) -> dict[str, Any]:
    if not file_id:
        return {"error": "file_id required", "tool": "archive_file"}
    file = db.session.get(File, int(file_id))
    if file is None:
        return {"error": "file not found", "tool": "archive_file"}
    if not file_allowed(file, scope):
        return {"error": "file out of scope", "tool": "archive_file"}

    result = {"tool": "archive_file", "file_id": file.id}
    if write_mode == "notify_only":
        return {**result, "applied": False}
    file_ops.archive_file(file)
    db.session.flush()
    return {**result, "applied": True}
