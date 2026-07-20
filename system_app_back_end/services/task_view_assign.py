"""Assign a task to at most one view."""

from __future__ import annotations

from models import Task, TaskView, db
from services.task_view_flags import apply_section_flag_to_membership

VIEW_PRIORITY = (
    "daily",
    "weekly",
    "monthly",
    "quarterly",
    "arrangements",
    "missions",
)


def view_priority(view_type: str) -> int:
    try:
        return VIEW_PRIORITY.index(view_type)
    except ValueError:
        return len(VIEW_PRIORITY)


def assign_task_view(
    task_id: int,
    view_type: str | None,
    *,
    section_name: str | None = None,
    topic_key: str | None = None,
    order_index: int | None = None,
    clear_section: bool = False,
) -> TaskView | None:
    """Set or clear the single view membership for a task."""
    task = db.session.get(Task, int(task_id))
    if task is None:
        raise ValueError("task not found")

    existing_rows = (
        TaskView.query.filter_by(task_id=int(task_id))
        .order_by(TaskView.id)
        .all()
    )

    if view_type is None:
        for row in existing_rows:
            db.session.delete(row)
        db.session.flush()
        return None

    membership = existing_rows[0] if existing_rows else None
    if membership is None:
        membership = TaskView(task_id=int(task_id), view_type=view_type)
        db.session.add(membership)
    else:
        membership.view_type = view_type
        for extra in existing_rows[1:]:
            db.session.delete(extra)

    if topic_key is not None:
        membership.topic_key = topic_key
    if order_index is not None:
        membership.order_index = order_index
    if clear_section:
        membership.section_name = None
    elif section_name is not None:
        membership.section_name = section_name

    apply_section_flag_to_membership(membership)
    db.session.flush()
    return membership
