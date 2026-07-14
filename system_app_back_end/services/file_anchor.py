"""Validate file anchor_topic_id references."""

from __future__ import annotations

from models import Topic, db


def validate_anchor_topic_id(anchor_topic_id: int | None) -> str | None:
    if anchor_topic_id is None:
        return None
    topic = db.session.get(Topic, int(anchor_topic_id))
    if topic is None or topic.archived_at is not None:
        return "anchor topic not found"
    if topic.type != "project":
        return "anchor topic must be a project"
    return None


def parts_topic_id_for_file(file) -> int:
    """Topic that owns parts for a file (anchor project or file's topic)."""
    anchor_id = getattr(file, "anchor_topic_id", None)
    if anchor_id is not None:
        return int(anchor_id)
    return int(file.topic_id)
