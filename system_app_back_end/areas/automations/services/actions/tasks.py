"""Task steps: send done tasks back to active."""

from __future__ import annotations

from datetime import datetime

from models import File, ObjectEmbed, Topic, db
from areas.objects.services.task_ops import unmark_tasks_in_lists


def task_list_ids_in_scope(resolved: dict) -> list[int]:
    """Task lists reach a topic through the file they are embedded in."""
    query = (
        db.session.query(ObjectEmbed.task_list_id)
        .join(File, File.id == ObjectEmbed.file_id)
        .join(Topic, Topic.id == File.topic_id)
        .filter(
            ObjectEmbed.task_list_id.isnot(None),
            File.archived_at.is_(None),
            Topic.workspace_id == int(resolved["workspace_id"]),
            Topic.archived_at.is_(None),
            Topic.is_template.is_(False),
        )
    )
    if resolved.get("topic_ids"):
        query = query.filter(File.topic_id.in_([int(i) for i in resolved["topic_ids"]]))
    if resolved.get("file_ids"):
        query = query.filter(File.id.in_([int(i) for i in resolved["file_ids"]]))
    return sorted({row[0] for row in query.all()})


def unmark_tasks(*, workspace_id: int, resolved_scope: dict, params: dict, now: datetime):
    if params.get("task_list_id") is not None:
        list_ids = [int(params["task_list_id"])]
        allowed = task_list_ids_in_scope(resolved_scope)
        if list_ids[0] not in allowed:
            return {"error": "that task list is not in this automation's scope"}
    else:
        list_ids = task_list_ids_in_scope(resolved_scope)

    tasks = unmark_tasks_in_lists(list_ids)
    return {
        "ok": True,
        "task_ids": [t.id for t in tasks],
        "summary": f"unmarked {len(tasks)} task(s)",
    }
