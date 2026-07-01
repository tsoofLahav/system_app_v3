from models import AutomationRule, Task, TaskView, db
from services.automation_dispatcher import dispatch_task_triggered
from services.automation_params import normalize_params, trigger_config
from services.automation_topics import AUTOMATIONS_TOPIC_KEY


def ensure_trigger_task(rule):
    """Create or update the view task for a task-triggered automation rule."""
    if rule.trigger_type != "task":
        return None

    params = normalize_params(rule.params, rule.key, rule.action_type)
    trigger = trigger_config(params) or {}
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
        task_view = TaskView(
            task_id=task.id,
            view_type=view_type,
            section_name=section_name,
            topic_key=AUTOMATIONS_TOPIC_KEY,
            order_index=_next_view_order(view_type, section_name),
        )
        db.session.add(task_view)
    else:
        task.title = title
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
