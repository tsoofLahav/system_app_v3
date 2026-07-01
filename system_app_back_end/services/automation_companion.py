from datetime import datetime

from models import AutomationCompanionTask, AutomationRun, Task, TaskView, Topic, db
from services.automation_params import companion_config, normalize_params
from services.automation_topics import AUTOMATIONS_TOPIC_KEY


def create_companion_task(rule, run, flow_key, payload, title=None, section_name=None):
    params = normalize_params(rule.params, rule.key, rule.action_type)
    companion = companion_config(params) or {}
    topic_id = payload.get("topic_id")
    run_id = run.id if isinstance(run, AutomationRun) else run.get("id")

    if rule.trigger_type == "task":
        from services.automation_trigger import ensure_trigger_task

        task = ensure_trigger_task(rule)
        if task is None:
            return None
        return _upsert_companion_link(
            task=task,
            rule_key=rule.key,
            run_id=run_id,
            flow_key=flow_key,
            topic_id=topic_id,
            payload=payload,
        )

    view_type = companion.get("view_type", "daily")
    section = section_name or companion.get("section_name", "Automations")
    resolved_title = title or rule.name

    task = Task(block_id=None, title=resolved_title, status="active")
    db.session.add(task)
    db.session.flush()
    _ensure_task_view(task, view_type, section)
    return _upsert_companion_link(
        task=task,
        rule_key=rule.key,
        run_id=run_id,
        flow_key=flow_key,
        topic_id=topic_id,
        payload=payload,
    )


def _upsert_companion_link(task, rule_key, run_id, flow_key, topic_id, payload):
    query = AutomationCompanionTask.query.filter_by(
        task_id=task.id,
        rule_key=rule_key,
        status="pending",
    )
    if topic_id is not None:
        query = query.filter_by(topic_id=int(topic_id))
    else:
        query = query.filter(AutomationCompanionTask.topic_id.is_(None))
    link = query.order_by(AutomationCompanionTask.id.desc()).first()
    if link is None:
        link = AutomationCompanionTask(
            task_id=task.id,
            rule_key=rule_key,
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
    task_id = link.task_id
    pending_count = AutomationCompanionTask.query.filter_by(
        task_id=task_id,
        status="pending",
    ).count()
    if pending_count == 0:
        task = db.session.get(Task, task_id)
        if task is not None:
            task.status = "done"
    db.session.flush()
    return link.to_dict()


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


def enrich_companion_dict(link):
    item = link.to_dict()
    payload = link.payload if link.payload is not None else {}
    topic = db.session.get(Topic, link.topic_id) if link.topic_id else None
    if topic is not None:
        item["topic_name"] = topic.name
        item["topic_color"] = topic.color
        item["topic_icon"] = topic.icon
        item["topic_type"] = topic.type
    elif payload.get("topic_name"):
        item["topic_name"] = payload["topic_name"]
    return item


def _is_process_companion_link(link, enriched=None):
    enriched = enriched if enriched is not None else enrich_companion_dict(link)
    topic_type = enriched.get("topic_type")
    if topic_type is not None:
        return topic_type == "process"
    if link.topic_id is None:
        return True
    topic = db.session.get(Topic, link.topic_id)
    return topic is not None and topic.type == "process"


def pending_companions_for_task(task_id):
    links = (
        AutomationCompanionTask.query.filter_by(task_id=int(task_id), status="pending")
        .order_by(AutomationCompanionTask.id)
        .all()
    )
    results = []
    for link in links:
        enriched = enrich_companion_dict(link)
        if _is_process_companion_link(link, enriched):
            results.append(enriched)
    return results


def pending_companions_by_task_ids(task_ids):
    if not task_ids:
        return {}
    links = (
        AutomationCompanionTask.query.filter(
            AutomationCompanionTask.task_id.in_(task_ids),
            AutomationCompanionTask.status == "pending",
        )
        .order_by(AutomationCompanionTask.id)
        .all()
    )
    grouped = {}
    for link in links:
        if not _is_process_companion_link(link):
            continue
        grouped.setdefault(link.task_id, []).append(link)
    return grouped
