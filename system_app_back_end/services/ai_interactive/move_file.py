"""AI move delegates to shared file move after topic match."""

from __future__ import annotations

from models import File, Topic, db
from services.ai_interactive.topic_router import match_file_to_topic
from services.file_move import move_file_to_topic


def run_move_file_to_topic(
    *,
    file_id: int,
    source_topic_id: int,
    locale: str = "en",
) -> dict:
    file = db.session.get(File, int(file_id))
    if file is None:
        raise ValueError("File not found")
    if file.archived_at is not None:
        raise ValueError("Cannot move an archived file")

    source_topic = db.session.get(Topic, int(source_topic_id))
    if source_topic is None:
        raise ValueError("Source topic not found")

    route = match_file_to_topic(
        file_id=file.id,
        source_topic_id=source_topic_id,
        locale=locale,
    )
    target_topic_id = int(route["topic_id"])
    target_topic = db.session.get(Topic, target_topic_id)
    if target_topic is None:
        raise ValueError("Target topic not found")

    moved = move_file_to_topic(file.id, target_topic_id)

    return {
        "tool": "move_file_to_topic",
        "action": "write",
        "result": moved.name,
        "source_topic_id": source_topic.id,
        "source_topic_name": source_topic.name,
        "target_topic_id": target_topic_id,
        "target_topic_name": target_topic.name if target_topic else route.get("topic_name"),
        "target_file_id": moved.id,
        "target_file_name": moved.name,
        "target_kind": "file",
        "route_reason": route.get("reason"),
    }
