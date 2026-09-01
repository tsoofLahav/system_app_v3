"""Task state as plain functions, callable without a request.

`status` is the whole story: `"active"`, `"done"`, `"inactive"`, or `"pending"`.
Unmarking a list is what a weekly reset does, so it lives here rather than in
a route. The minute cron also promotes pending tasks whose date has arrived.
"""

from __future__ import annotations

from datetime import date, datetime, timezone
from zoneinfo import ZoneInfo

from models import Task, ViewTaskMembership, db

ACTIVE = "active"
DONE = "done"
INACTIVE = "inactive"
PENDING = "pending"

# Calendar day for pending → active, matching automation schedules.
_ACTIVATE_TZ = ZoneInfo("Asia/Jerusalem")


def today_in_app(now: datetime | None = None) -> date:
    moment = now or datetime.now(timezone.utc)
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=timezone.utc)
    return moment.astimezone(_ACTIVATE_TZ).date()


def due_day(value) -> date | None:
    if value is None:
        return None
    if isinstance(value, datetime):
        return value.date()
    if isinstance(value, date):
        return value
    return None


def should_activate_pending(status: str, due_date, today: date) -> bool:
    if status != PENDING:
        return False
    day = due_day(due_date)
    if day is None:
        return False
    return day <= today


def task_has_view(task: Task) -> bool:
    task_id = getattr(task, "id", None)
    if not task_id:
        return bool(getattr(task, "complimentary_role", None))
    return (
        ViewTaskMembership.query.filter_by(task_id=int(task_id)).count() > 0
    )


def unmarked_status_for(task: Task, *, has_view: bool | None = None) -> str:
    if has_view is None:
        has_view = task_has_view(task)
    return ACTIVE if has_view else INACTIVE


def set_task_status(task: Task, *, done: bool) -> Task:
    if done:
        task.status = DONE
        return task
    task.status = unmarked_status_for(task)
    return task


def toggle_task(task: Task) -> Task:
    if task.status in (INACTIVE, PENDING):
        return task
    return set_task_status(task, done=task.status != DONE)


def sync_status_with_memberships(task: Task) -> Task:
    """Inactive = no view. Pending needs a view. Done is left alone."""
    if task.status == DONE:
        return task
    has_view = task_has_view(task)
    if task.status == PENDING:
        if not has_view:
            task.status = INACTIVE
        return task
    task.status = ACTIVE if has_view else INACTIVE
    return task


def activate_due_pending_tasks(*, now: datetime | None = None) -> list[Task]:
    """Pending with a due date on or before today in Asia/Jerusalem → active."""
    today = today_in_app(now)
    tasks = (
        Task.query.filter(
            Task.status == PENDING,
            Task.archived_at.is_(None),
            Task.due_date.isnot(None),
        )
        .order_by(Task.id)
        .all()
    )
    changed: list[Task] = []
    for task in tasks:
        if not should_activate_pending(task.status, task.due_date, today):
            continue
        task.status = ACTIVE
        changed.append(task)
    if changed:
        db.session.flush()
    return changed


def unmark_tasks_in_lists(task_list_ids) -> list[Task]:
    """Send every done task in these lists back to active or inactive.

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
