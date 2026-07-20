"""Bulk reorder for task view memberships."""

from __future__ import annotations

from models import TaskView, db


def reorder_task_views(
    view_type: str,
    ordered_task_ids: list[int],
    *,
    section_name: str | None = None,
) -> list[TaskView]:
    if not ordered_task_ids:
        return []
    if len(set(ordered_task_ids)) != len(ordered_task_ids):
        raise ValueError("duplicate task ids")

    query = TaskView.query.filter(
        TaskView.view_type == view_type,
        TaskView.task_id.isnot(None),
        TaskView.task_id.in_(ordered_task_ids),
    )
    if section_name is None:
        query = query.filter(TaskView.section_name.is_(None))
    else:
        query = query.filter(TaskView.section_name == section_name)

    memberships = query.all()
    if len(memberships) != len(ordered_task_ids):
        raise ValueError("task ids must belong to view group")

    by_task_id = {membership.task_id: membership for membership in memberships}
    for index, task_id in enumerate(ordered_task_ids):
        by_task_id[task_id].order_index = index

    db.session.flush()
    return [by_task_id[task_id] for task_id in ordered_task_ids]
