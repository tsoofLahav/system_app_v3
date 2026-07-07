"""Move a file to another topic's additional files (no AI)."""

from __future__ import annotations

from models import File, Topic, db
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


def move_file_to_topic(file_id: int, target_topic_id: int) -> File:
    file = db.session.get(File, int(file_id))
    if file is None:
        raise ValueError("File not found")
    if file.archived_at is not None:
        raise ValueError("Cannot move an archived file")

    target_topic = db.session.get(Topic, int(target_topic_id))
    if target_topic is None:
        raise ValueError("Target topic not found")
    if target_topic.archived_at is not None:
        raise ValueError("Cannot move into an archived topic")
    if file.topic_id == target_topic_id:
        raise ValueError("File is already in this topic")

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

    return file
