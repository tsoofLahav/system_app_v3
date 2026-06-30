from datetime import datetime

from models import AutomationCompanionTask, AutomationRun, Task, TaskView, Topic, db
from services.automation_params import companion_config, normalize_params, trigger_config
from services.automation_topics import AUTOMATIONS_TOPIC_KEY


def create_companion_task(rule, run, flow_key, payload, title, section_name=None):
    params = normalize_params(rule.params, rule.key, rule.action_type)
    companion = companion_config(params) or {}
    view_type = companion.get("view_type", "weekly")
    section = section_name or companion.get("section_name", "Automations")
    topic_id = payload.get("topic_id")

    task = _resolve_companion_task(rule, title)
    if task is None:
        task = Task(block_id=None, title=title, status="active")
        db.session.add(task)
        db.session.flush()

    _ensure_task_view(task, view_type, section)

    run_id = run.id if isinstance(run, AutomationRun) else run.get("id")
    link = (
        AutomationCompanionTask.query.filter_by(
            task_id=task.id,
            rule_key=rule.key,
            status="pending",
        )
        .order_by(AutomationCompanionTask.id.desc())
        .first()
    )
    if link is None:
        link = AutomationCompanionTask(
            task_id=task.id,
            rule_key=rule.key,
            automation_run_id=run_id,
            flow_key=flow_key,
            topic_id=int(topic_id) if topic_id is not None else None,
            payload=payload or {},
            status="pending",
        )
        db.session.add(link)
    else:
        link.automation_run_id = run_id
        link.flow_key = flow_key
        link.topic_id = int(topic_id) if topic_id is not None else None
        link.payload = payload or {}
        link.status = "pending"
        link.completed_at = None
    db.session.flush()
    return link.to_dict()


def complete_companion_task(companion_id):
    link = db.session.get(AutomationCompanionTask, companion_id)
    if link is None:
        return None
    link.status = "completed"
    link.completed_at = datetime.utcnow()
    task = db.session.get(Task, link.task_id)
    if task is not None:
        task.status = "done"
    db.session.flush()
    return link.to_dict()


def _resolve_companion_task(rule, title):
    if rule.trigger_type != "task":
        return None
    params = normalize_params(rule.params, rule.key, rule.action_type)
    trigger = trigger_config(params) or {}
    task_id = trigger.get("task_id")
    if not task_id:
        return None
    task = db.session.get(Task, int(task_id))
    if task is None:
        return None
    task.title = title
    return task


def _ensure_task_view(task, view_type, section_name):
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


def _next_view_order(view_type, section_name):
    last = (
        TaskView.query.filter_by(view_type=view_type, section_name=section_name)
        .order_by(TaskView.order_index.desc(), TaskView.id.desc())
        .first()
    )
    if last is None or last.order_index is None:
        return 0
    return last.order_index + 1


def companion_title(rule, topic, template=None):
    params = normalize_params(rule.params, rule.key, rule.action_type)
    companion = companion_config(params) or {}
    pattern = template or companion.get("title_template") or "{topic_name}"
    topic_name = topic.name if topic else "Unknown"
    if topic_name == "main":
        topic_name = "Main"
    return pattern.format(topic_name=topic_name, rule_name=rule.name)
