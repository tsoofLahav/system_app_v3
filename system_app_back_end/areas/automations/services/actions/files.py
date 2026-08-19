"""File steps: make one, archive some."""

from __future__ import annotations

from datetime import datetime, timedelta

from models import File, Topic, TopicType, db
from areas.automations.services.scope import target_topic_id
from areas.automations.services.steps import expand_name_tokens
from areas.files.services import file_ops
from areas.files.services.clone_topic_skeleton import clone_slot_into_topic


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


def _template_source_for(topic: Topic) -> Topic | None:
    if topic.topic_type_id is None:
        return None
    type_row = db.session.get(TopicType, topic.topic_type_id)
    if type_row is None or not type_row.template_topic_id:
        return None
    return db.session.get(Topic, type_row.template_topic_id)


def create_file(*, workspace_id: int, resolved_scope: dict, params: dict, now: datetime):
    slot = str(params.get("template_slot") or "").strip()
    if slot:
        created: list[File] = []
        for topic_id in _topics_in_scope(resolved_scope):
            topic = db.session.get(Topic, int(topic_id))
            if topic is None or int(topic.workspace_id) != int(workspace_id):
                continue
            source = _template_source_for(topic)
            if source is None:
                continue
            file = clone_slot_into_topic(
                topic, source=source, template_slot=slot
            )
            if file is None:
                continue
            name = str(params.get("name") or "").strip()
            if name:
                file.name = expand_name_tokens(name, now=now)
            created.append(file)
        db.session.flush()
        return {
            "ok": True,
            "file_ids": [f.id for f in created],
            "summary": f"created {len(created)} file(s)",
        }

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
    slot = str(params.get("template_slot") or "").strip()
    if slot:
        files = [
            f
            for f in files
            if str((f.meta or {}).get("template_slot") or "") == slot
        ]
    for file in files:
        file_ops.archive_file(file, when=now)
    db.session.flush()
    return {
        "ok": True,
        "file_ids": [f.id for f in files],
        "summary": f"archived {len(files)} file(s)",
    }
