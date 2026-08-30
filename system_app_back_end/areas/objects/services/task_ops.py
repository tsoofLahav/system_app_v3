"""Task state as plain functions, callable without a request.

`status` is the whole story: `"active"` or `"done"`. Unmarking a list is what a
weekly reset does, so it lives here rather than in a route.
"""

from __future__ import annotations

from models import Task, db

ACTIVE = "active"
DONE = "done"


def set_task_status(task: Task, *, done: bool) -> Task:
    task.status = DONE if done else ACTIVE
    return task


def toggle_task(task: Task) -> Task:
    if task.complimentary_role:
        raise ValueError("complimentary tasks are completed by their automation, not the checkbox")
    return set_task_status(task, done=task.status != DONE)


def unmark_tasks_in_lists(task_list_ids) -> list[Task]:
    """Send every done task in these lists back to active.

    Returns the tasks it changed, so a caller can report "4 tasks" rather than
    "done". Archived tasks stay where they are — they are deleted rows in all
    but name.
    """
    ids = [int(i) for i in task_list_ids]
    if not ids:
        return []
    tasks = (
        Task.query.filter(
            Task.task_list_id.in_(ids),
            Task.status == DONE,
            Task.archived_at.is_(None),
        )
        .order_by(Task.id)
        .all()
    )
    for task in tasks:
        set_task_status(task, done=False)
    db.session.flush()
    return tasks
