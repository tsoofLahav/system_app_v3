"""Move a file into another topic's additional files."""

from __future__ import annotations

from models import File, Topic, db
from services.ai_interactive.topic_router import match_file_to_topic
from services.automation_dispatcher import (
    dispatch_file_moved_to_additional,
    file_qualifies_as_moved_to_additional,
)


def _next_topic_file_order(topic_id: int) -> int:
    last = (
        File.query.filter_by(topic_id=int(topic_id))
        .filter(File.archived_at.is_(None))
        .order_by(File.order_index.desc(), File.id.desc())
        .first()
    )
    if last is None or last.order_index is None:
        return 0
    return last.order_index + 1


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

    prev_is_main = file.is_main
    prev_topic_id = file.topic_id

    file.topic_id = target_topic_id
    file.is_main = False
    file.order_index = _next_topic_file_order(target_topic_id)

    db.session.commit()

    if file_qualifies_as_moved_to_additional(
        file,
        prev_is_main=prev_is_main,
        prev_topic_id=prev_topic_id,
    ):
        dispatch_file_moved_to_additional(
            file,
            change="file_moved_to_additional",
            meta={"source_topic_id": prev_topic_id},
        )

    return {
        "tool": "move_file_to_topic",
        "action": "write",
        "result": file.name,
        "source_topic_id": source_topic.id,
        "source_topic_name": source_topic.name,
        "target_topic_id": target_topic_id,
        "target_topic_name": target_topic.name if target_topic else route.get("topic_name"),
        "target_file_id": file.id,
        "target_file_name": file.name,
        "target_kind": "file",
        "route_reason": route.get("reason"),
    }
