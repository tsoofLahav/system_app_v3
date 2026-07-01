from models import AutomationRule, Task, TaskView, db
from services.automation_dispatcher import dispatch_task_triggered
from services.automation_params import normalize_params, trigger_config
from services.automation_topics import AUTOMATIONS_TOPIC_KEY


def _trigger_from_rule(rule):
    params = normalize_params(rule.params, rule.key, rule.action_type)
    return trigger_config(params) or {}, params


def hide_trigger_task(rule):
    """Remove the trigger task from view panes; keep task_id in params for reuse."""
    trigger, params = _trigger_from_rule(rule)
    task_id = trigger.get("task_id")
    if not task_id:
        return None
    TaskView.query.filter_by(task_id=int(task_id)).delete(synchronize_session=False)
    task = db.session.get(Task, int(task_id))
    if task is not None:
        task.status = "done"
    rule.params = params
    db.session.flush()
    return task


def ensure_trigger_task(rule):
    """Create or restore the single trigger task for a task-triggered automation rule."""
    if rule.trigger_type != "task":
        return None

    trigger, params = _trigger_from_rule(rule)
    view_type = trigger.get("view_type")
    section_name = trigger.get("section_name")
    if not view_type:
        raise ValueError("trigger.view_type is required for task-triggered rules")

    task_id = trigger.get("task_id")
    task = db.session.get(Task, int(task_id)) if task_id else None
    title = trigger.get("title") or rule.name

    if task is None:
        task = Task(block_id=None, title=title, status="done")
        db.session.add(task)
        db.session.flush()
    else:
        task.title = title
        if task.archived_at is not None:
            task.archived_at = None
        if task.status not in {"done", "active"}:
            task.status = "done"

    membership = (
        TaskView.query.filter_by(task_id=task.id, view_type=view_type)
        .order_by(TaskView.id)
        .first()
    )
    if membership is None:
        membership = TaskView(
            task_id=task.id,
            view_type=view_type,
            section_name=section_name,
            topic_key=AUTOMATIONS_TOPIC_KEY,
            order_index=_next_view_order(view_type, section_name),
        )
        db.session.add(membership)
    else:
        membership.section_name = section_name
        membership.topic_key = AUTOMATIONS_TOPIC_KEY

    trigger["task_id"] = task.id
    trigger["view_type"] = view_type
    if section_name is not None:
        trigger["section_name"] = section_name
    params["trigger"] = trigger
    rule.params = params
    db.session.flush()
    return task


def handle_task_status_change(task, previous_status):
    if previous_status != "done" or task.status != "active":
        return []
    return dispatch_task_triggered(task.id)


def _next_view_order(view_type, section_name):
    last = (
        TaskView.query.filter_by(view_type=view_type, section_name=section_name)
        .order_by(TaskView.order_index.desc(), TaskView.id.desc())
        .first()
    )
    if last is None or last.order_index is None:
        return 0
    return last.order_index + 1
