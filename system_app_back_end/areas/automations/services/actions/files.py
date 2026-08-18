"""File steps: make one, archive some."""

from __future__ import annotations

from datetime import datetime, timedelta

from models import File, Topic, db
from areas.automations.services.scope import target_topic_id
from areas.automations.services.steps import expand_name_tokens
from areas.files.services import file_ops


def _topics_in_scope(resolved: dict) -> list[int]:
    topic_ids = resolved.get("topic_ids")
    if topic_ids:
        return [int(i) for i in topic_ids]
    rows = (
        db.session.query(Topic.id)
        .filter(Topic.workspace_id == int(resolved["workspace_id"]))
        .all()
    )
    return [row[0] for row in rows]


def files_in_scope(resolved: dict, *, older_than: datetime | None = None):
    query = File.query.filter(
        File.topic_id.in_(_topics_in_scope(resolved)),
        File.archived_at.is_(None),
    )
    if resolved.get("file_ids"):
        query = query.filter(File.id.in_([int(i) for i in resolved["file_ids"]]))
    if older_than is not None:
        query = query.filter(File.created_at < older_than)
    return query.order_by(File.id).all()


def create_file(*, workspace_id: int, resolved_scope: dict, params: dict, now: datetime):
    topic_id = params.get("topic_id") or target_topic_id(resolved_scope)
    if topic_id is None:
        return {"error": "no topic to create in: scope covers more than one"}

    topic = db.session.get(Topic, int(topic_id))
    if topic is None or int(topic.workspace_id) != int(workspace_id):
        return {"error": "topic not found in this workspace"}

    name = expand_name_tokens(params.get("name") or "", now=now)
    try:
        file = file_ops.create_file(topic_id=topic.id, name=name)
    except ValueError as error:
        return {"error": str(error)}
    return {"ok": True, "file_id": file.id, "summary": f"created “{name}”"}


def archive_files(*, workspace_id: int, resolved_scope: dict, params: dict, now: datetime):
    older_than = None
    if params.get("older_than_days") is not None:
        older_than = now - timedelta(days=int(params["older_than_days"]))

    chosen = params.get("file_ids")
    scope = dict(resolved_scope)
    if chosen:
        scope["file_ids"] = [int(i) for i in chosen]

    files = files_in_scope(scope, older_than=older_than)
    for file in files:
        file_ops.archive_file(file, when=now)
    db.session.flush()
    return {
        "ok": True,
        "file_ids": [f.id for f in files],
        "summary": f"archived {len(files)} file(s)",
    }
