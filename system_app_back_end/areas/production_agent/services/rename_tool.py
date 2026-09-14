"""Agent rename tool — topic name, file name, or a topic's type."""

from __future__ import annotations

from typing import Any

from models import File, Topic, TopicType, db
from areas.files.services.system_topics import is_system_topic
from areas.production_agent.services.browse_tools import file_allowed
from areas.production_agent.services.write_tools import WriteMode

TARGETS = {"topic", "file", "topic_type"}


def _clean(value: str) -> str:
    return str(value or "").strip()


def rename_tool(
    *,
    workspace_id: int,
    target: str,
    topic_id: int | None,
    file_id: int | None,
    name: str,
    topic_type: str,
    write_mode: WriteMode,
) -> dict[str, Any]:
    target = (target or "").strip().lower()
    if target not in TARGETS:
        return {"error": "target must be topic | file | topic_type", "tool": "rename"}

    if target == "topic":
        return _rename_topic(workspace_id, topic_id, name, write_mode)
    if target == "file":
        return _rename_file(workspace_id, file_id, name, write_mode)
    return _set_topic_type(workspace_id, topic_id, topic_type, write_mode)


def _rename_topic(
    workspace_id: int, topic_id: int | None, name: str, write_mode: WriteMode
) -> dict[str, Any]:
    if not topic_id:
        return {"error": "topic_id required", "tool": "rename"}
    topic = db.session.get(Topic, int(topic_id))
    if topic is None or int(topic.workspace_id) != int(workspace_id):
        return {"error": "topic not found", "tool": "rename"}
    if is_system_topic(topic):
        return {"error": "system topics cannot be renamed", "tool": "rename"}
    clean_name = _clean(name)
    if not clean_name:
        return {"error": "name required", "tool": "rename"}

    result = {
        "tool": "rename",
        "target": "topic",
        "topic_id": topic.id,
        "name": clean_name,
        "write_mode": write_mode,
    }
    if write_mode in ("notify_only", "review"):
        return {**result, "applied": False}
    topic.name = clean_name
    db.session.commit()
    return {**result, "applied": True}


def _rename_file(
    workspace_id: int, file_id: int | None, name: str, write_mode: WriteMode
) -> dict[str, Any]:
    if not file_id:
        return {"error": "file_id required", "tool": "rename"}
    file = db.session.get(File, int(file_id))
    if file is None:
        return {"error": "file not found", "tool": "rename"}
    if not file_allowed(file, {"workspace_id": workspace_id}):
        return {"error": "file out of scope", "tool": "rename"}
    clean_name = _clean(name)
    if not clean_name:
        return {"error": "name required", "tool": "rename"}

    result = {
        "tool": "rename",
        "target": "file",
        "file_id": file.id,
        "name": clean_name,
        "write_mode": write_mode,
    }
    if write_mode in ("notify_only", "review"):
        return {**result, "applied": False}
    file.name = clean_name
    db.session.commit()
    return {**result, "applied": True}


def _set_topic_type(
    workspace_id: int, topic_id: int | None, topic_type: str, write_mode: WriteMode
) -> dict[str, Any]:
    if not topic_id:
        return {"error": "topic_id required", "tool": "rename"}
    topic = db.session.get(Topic, int(topic_id))
    if topic is None or int(topic.workspace_id) != int(workspace_id):
        return {"error": "topic not found", "tool": "rename"}
    if is_system_topic(topic):
        return {"error": "system topics cannot be edited", "tool": "rename"}

    clean_type = _clean(topic_type)
    type_row: TopicType | None = None
    if clean_type:
        type_row = (
            TopicType.query.filter_by(workspace_id=workspace_id)
            .filter(db.func.lower(TopicType.name) == clean_type.lower())
            .first()
        )
        if type_row is None:
            names = [
                t.name
                for t in TopicType.query.filter_by(workspace_id=workspace_id).all()
            ]
            return {
                "error": f"topic type not found; existing types: {names}",
                "tool": "rename",
            }

    result = {
        "tool": "rename",
        "target": "topic_type",
        "topic_id": topic.id,
        "topic_type": type_row.name if type_row else "",
        "write_mode": write_mode,
    }
    if write_mode in ("notify_only", "review"):
        return {**result, "applied": False}
    topic.topic_type_id = type_row.id if type_row else None
    db.session.commit()
    return {**result, "applied": True}
