from datetime import datetime

from models import AutomationRule, AutomationRun, File, Topic, db
from services.automation_params import binding_files, normalize_params
from services.automation_definitions import validate_rule_activation
from services.automation_runner import enqueue_run
from services.automation_schedule import next_run_after


def resolve_scope_topics(rule):
    params = normalize_params(rule.params, rule.key, rule.action_type)
    scope = params.get("scope") or {}
    kind = scope.get("kind", "all")

    query = Topic.query.filter(Topic.archived_at.is_(None))
    if kind == "topic_type":
        topic_type = scope.get("topic_type")
        if not topic_type:
            return []
        return query.filter_by(type=topic_type).order_by(Topic.id).all()
    if kind == "topic":
        if scope.get("topic_id"):
            topic = db.session.get(Topic, int(scope["topic_id"]))
            return [topic] if topic and topic.archived_at is None else []
        topic_name = scope.get("topic_name")
        if topic_name:
            topic = Topic.query.filter_by(name=topic_name).first()
            return [topic] if topic and topic.archived_at is None else []
        return []
    if kind == "all":
        return query.order_by(Topic.id).all()
    return []


def topic_in_scope(rule, topic_id):
    if topic_id is None:
        return False
    topics = resolve_scope_topics(rule)
    return any(topic.id == int(topic_id) for topic in topics)


def file_matches_binding(file, binding, topic_id):
    if file is None or file.topic_id != int(topic_id):
        return False
    if binding.get("file_id") is not None:
        return int(binding["file_id"]) == file.id

    match = binding.get("match") or {}
    if not match and binding.get("name"):
        match = {"name": binding["name"]}
    if not match:
        return False

    if match.get("type") and file.type != match["type"]:
        return False
    if match.get("name") and file.name != match["name"]:
        return False
    if "is_main" in match and bool(file.is_main) != bool(match["is_main"]):
        return False
    return True


def rule_matches_file_event(rule, file):
    if rule.trigger_type != "event":
        return False
    if file.type == "overview":
        return False
    params = normalize_params(rule.params, rule.key, rule.action_type)
    event_name = params.get("event") or params.get("trigger", {}).get("event")
    if event_name and event_name != "file_changed":
        return False
    if not topic_in_scope(rule, file.topic_id):
        return False
    bindings = binding_files(params)
    if not bindings:
        return False
    event_bindings = [
        binding
        for binding in bindings
        if binding.get("role") != "overview"
    ]
    if not event_bindings:
        return False
    return any(
        file_matches_binding(file, binding, file.topic_id)
        for binding in event_bindings
    )


def _enqueue_for_rule(rule, trigger_source, event_context=None):
    activation_error = validate_rule_activation(rule, trigger_source=trigger_source)
    if activation_error:
        now = datetime.utcnow()
        run = AutomationRun(
            rule_id=rule.id,
            status="failed",
            trigger_source=trigger_source,
            event_context=event_context or {},
            result={},
            error=activation_error,
            started_at=now,
            finished_at=now,
        )
        db.session.add(run)
        db.session.flush()
        return run.id

    context = dict(event_context or {})
    run = enqueue_run(rule, trigger_source=trigger_source, event_context=context)
    return run["id"] if run else None


def dispatch_scheduled_rule(rule, trigger_source="schedule"):
    topics = resolve_scope_topics(rule)
    run_ids = []
    if len(topics) <= 1:
        topic = topics[0] if topics else None
        context = {"topic_id": topic.id} if topic else {}
        context["scheduled"] = True
        run_id = _enqueue_for_rule(rule, trigger_source, context)
        if run_id is not None:
            run_ids.append(run_id)
        return run_ids

    for topic in topics:
        run_id = _enqueue_for_rule(
            rule,
            trigger_source,
            {"topic_id": topic.id, "scheduled": True},
        )
        if run_id is not None:
            run_ids.append(run_id)
    return run_ids


def dispatch_manual_rule(rule):
    return dispatch_scheduled_rule(rule, trigger_source="manual")


def dispatch_task_triggered(task_id):
    from services.automation_trigger_lookup import rules_for_trigger_task

    run_ids = []
    for rule in rules_for_trigger_task(task_id):
        topics = resolve_scope_topics(rule)
        if not topics:
            run_id = _enqueue_for_rule(
                rule,
                "task",
                {"task_id": int(task_id), "trigger": "task_unchecked"},
            )
            if run_id is not None:
                run_ids.append(run_id)
            continue

        for topic in topics:
            run_id = _enqueue_for_rule(
                rule,
                "task",
                {
                    "task_id": int(task_id),
                    "topic_id": topic.id,
                    "trigger": "task_unchecked",
                },
            )
            if run_id is not None:
                run_ids.append(run_id)
    return run_ids


def dispatch_file_changed(file_id, change, meta=None):
    file = db.session.get(File, int(file_id)) if file_id is not None else None
    if file is None:
        return []

    from flask import current_app

    from services.automation_change_triggers import (
        change_trigger_config_for_rule,
        process_due_change_triggers,
        record_change_event,
    )

    try:
        app = current_app._get_current_object()
    except RuntimeError:
        app = None

    rules = AutomationRule.query.filter_by(enabled=True, trigger_type="event").all()
    run_ids = []
    for rule in rules:
        if not rule_matches_file_event(rule, file):
            continue
        context = {
            "event": "file_changed",
            "file_id": file.id,
            "topic_id": file.topic_id,
            "change": change,
        }
        if meta:
            context.update(meta)

        if change_trigger_config_for_rule(rule) is not None:
            record_change_event(rule, context, app=app)
            continue

        run_id = _enqueue_for_rule(rule, "event", context)
        if run_id is not None:
            run_ids.append(run_id)

    if run_ids and app is not None:
        from services.automation_runner import kick_run_async

        for run_id in run_ids:
            kick_run_async(app, run_id)

    if app is not None:
        process_due_change_triggers(app=app)

    return run_ids


def dispatch_due_scheduled_rules(now=None):
    from datetime import datetime

    now = now or datetime.utcnow()
    rules = (
        AutomationRule.query.filter_by(enabled=True, trigger_type="schedule")
        .filter(AutomationRule.next_run_at <= now)
        .order_by(AutomationRule.next_run_at, AutomationRule.id)
        .all()
    )
    results = []
    for rule in rules:
        run_ids = dispatch_scheduled_rule(rule)
        if run_ids and rule.schedule:
            rule.next_run_at = next_run_after(
                rule.schedule, now, timezone=rule.timezone
            )
        results.append({"rule_id": rule.id, "run_ids": run_ids})
    db.session.commit()
    return results
