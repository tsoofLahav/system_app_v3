from models import Task, TaskView, db
from services.automation_definitions import get_definition, rule_uses_companion_trigger_task
from services.automation_dispatcher import dispatch_task_triggered
from services.automation_params import (
    persist_rule_params,
    rule_params_snapshot,
    trigger_config,
)
from services.automation_topics import AUTOMATIONS_TOPIC_KEY


def _trigger_from_params(params):
    trigger = trigger_config(params) or {}
    return dict(trigger), params


def stored_trigger_task_id(rule, params=None):
    """Canonical trigger task id for this automation rule (persisted on the rule)."""
    params = params if params is not None else rule_params_snapshot(rule)
    trigger = trigger_config(params) or {}
    task_id = trigger.get("task_id")
    return int(task_id) if task_id else None


def hide_trigger_task(rule):
    """Remove the trigger task from view panes; keep task_id in params for reuse."""
    params = rule_params_snapshot(rule)
    task_id = stored_trigger_task_id(rule, params)
    if not task_id:
        return None
    TaskView.query.filter_by(task_id=task_id).delete(synchronize_session=False)
    task = db.session.get(Task, task_id)
    if task is not None:
        task.status = "done"
    persist_rule_params(rule, params)
    db.session.flush()
    return task


def ensure_trigger_task(rule):
    """Create or restore the shared companion trigger task for an automation rule."""
    definition = get_definition(rule.key, rule.action_type)
    uses_shared = rule_uses_companion_trigger_task(rule)
    if not uses_shared and rule.trigger_type != "task":
        return None

    params = rule_params_snapshot(rule)
    trigger, params = _trigger_from_params(params)
    view_type = trigger.get("view_type")
    section_name = trigger.get("section_name")
    if not view_type:
        raise ValueError("trigger.view_type is required for task-triggered rules")

    title = trigger.get("title") or rule.name
    task_id = stored_trigger_task_id(rule, params) or _recover_trigger_task_id(
        rule, trigger, title
    )
    task = db.session.get(Task, task_id) if task_id else None

    if task is None:
        task = Task(block_id=None, title=title, status="done")
        db.session.add(task)
        db.session.flush()
        task_id = task.id
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
    trigger["rule_id"] = rule.id
    trigger["view_type"] = view_type
    if section_name is not None:
        trigger["section_name"] = section_name
    params["trigger"] = trigger
    persist_rule_params(rule, params)
    db.session.flush()
    return task


def _recover_trigger_task_id(rule, trigger, title):
    """Reuse an existing automations-topic row when params lost task_id (legacy orphans)."""
    view_type = trigger.get("view_type")
    if not view_type:
        return None
    section_name = trigger.get("section_name")
    query = (
        db.session.query(Task.id)
        .join(TaskView, TaskView.task_id == Task.id)
        .filter(TaskView.view_type == view_type)
        .filter(TaskView.topic_key == AUTOMATIONS_TOPIC_KEY)
        .filter(Task.title == title)
        .filter(Task.archived_at.is_(None))
    )
    if section_name:
        query = query.filter(TaskView.section_name == section_name)
    row = query.order_by(Task.id).first()
    return int(row[0]) if row else None


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
