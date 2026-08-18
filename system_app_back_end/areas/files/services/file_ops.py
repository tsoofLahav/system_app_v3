"""File lifecycle as plain functions, callable without a request.

The HTTP routes used to be the only way to create or archive a file, which is
fine until a background job wants the same thing. These take arguments instead
of `request`, raise `ValueError` instead of aborting, and leave the commit to
the caller — the automation runner commits once for a whole series.
"""

from __future__ import annotations

from datetime import datetime

from models import File, Topic, db
from areas.files.services.document_v3 import empty_document_json


def create_file(
    *,
    topic_id: int,
    name: str,
    document_json: str | None = None,
    order_index: int = 0,
    meta: dict | None = None,
) -> File:
    name = (name or "").strip()
    if not name:
        raise ValueError("file name is required")
    topic = db.session.get(Topic, int(topic_id))
    if topic is None:
        raise ValueError("topic not found")

    file = File(
        topic_id=topic.id,
        name=name,
        document_json=document_json or empty_document_json(),
        order_index=order_index,
        meta=meta or {},
    )
    db.session.add(file)
    db.session.flush()
    return file


def archive_file(file: File, *, when: datetime | None = None) -> File:
    """Archiving is a timestamp, not a move: the file stays in its topic and
    becomes read-only."""
    if file.archived_at is None:
        file.archived_at = when or datetime.utcnow()
    return file


def move_file_to_topic(file: File, *, topic_id: int) -> File:
    topic = db.session.get(Topic, int(topic_id))
    if topic is None:
        raise ValueError("topic not found")
    file.topic_id = topic.id
    return file
