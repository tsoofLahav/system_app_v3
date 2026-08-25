"""Agent create_file tool — a new empty file in a topic, then patch to fill."""

from __future__ import annotations

from typing import Any

from models import Topic, db
from areas.files.services import file_ops
from areas.production_agent.services.write_tools import WriteMode


def create_file(
    *,
    topic_id: int,
    name: str,
    scope: dict,
    write_mode: WriteMode,
) -> dict[str, Any]:
    topic = db.session.get(Topic, topic_id)
    if topic is None:
        return {"error": "topic not found", "tool": "create_file"}
    workspace_id = scope.get("workspace_id")
    if workspace_id is not None and int(topic.workspace_id) != int(workspace_id):
        return {"error": "topic out of scope", "tool": "create_file"}
    if topic.archived_at is not None:
        return {"error": "archived topics are read-only", "tool": "create_file"}

    try:
        file = file_ops.create_file(
            topic_id=topic.id,
            name=name,
            place_first=True,
        )
    except ValueError as err:
        return {"error": str(err), "tool": "create_file"}

    result: dict[str, Any] = {
        "tool": "create_file",
        "file_id": file.id,
        "topic_id": topic.id,
        "name": file.name,
        "topic": topic.name or "",
        "write_mode": write_mode,
    }
    if write_mode == "notify_only":
        return {**result, "applied": False}
    if write_mode == "review":
        # Flushed in-session so later open_file / patch see it; run may roll back.
        return {**result, "applied": False}
    return {**result, "applied": True}
