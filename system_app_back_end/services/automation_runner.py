import threading
from datetime import datetime, timedelta

from models import AutomationRule, AutomationRun, db
from services.automation_actions import run_action
from services.automation_definitions import validate_rule_activation

ACTIVE_RUN_STATUSES = ("queued", "running")
STALE_ACTIVE_AFTER = timedelta(minutes=30)


def _mark_stale_active_run(run, now):
    run.status = "failed"
    run.error = f"stale {run.status} run cleared"
    run.finished_at = now


def _clear_stale_active_run(run, now):
    if run.status not in ACTIVE_RUN_STATUSES or run.finished_at is not None:
        return False
    started_at = run.started_at or now
    if now - started_at < STALE_ACTIVE_AFTER:
        return False
    _mark_stale_active_run(run, now)
    return True


def _clear_stale_active_runs(now):
    stale_runs = (
        AutomationRun.query.filter(AutomationRun.status.in_(ACTIVE_RUN_STATUSES))
        .filter(AutomationRun.finished_at.is_(None))
        .filter(AutomationRun.started_at < now - STALE_ACTIVE_AFTER)
        .all()
    )
    for run in stale_runs:
        _mark_stale_active_run(run, now)
    return stale_runs


def kick_run_async(app, run_id):
    def work():
        with app.app_context():
            try:
                process_run(run_id)
            except Exception:
                app.logger.exception(
                    "background automation run failed for run_id=%s",
                    run_id,
                )

    threading.Thread(target=work, daemon=True).start()


def enqueue_run(rule, trigger_source, event_context=None):
    now = datetime.utcnow()
    event_context = event_context or {}
    topic_id = event_context.get("topic_id")
    target_view = event_context.get("target_view")

    active_runs = (
        AutomationRun.query.filter_by(rule_id=rule.id)
        .filter(AutomationRun.status.in_(ACTIVE_RUN_STATUSES))
        .all()
    )
    for existing in active_runs:
        existing_topic = (existing.event_context or {}).get("topic_id")
        existing_target_view = (existing.event_context or {}).get("target_view")
        if topic_id is None and target_view is not None:
            if existing_target_view != target_view:
                continue
            if _clear_stale_active_run(existing, now):
                db.session.commit()
                break
            return existing.to_dict()
        if topic_id is None and existing_topic is None:
            if existing_target_view is not None:
                continue
            if _clear_stale_active_run(existing, now):
                db.session.commit()
                break
            return existing.to_dict()
        if topic_id is not None and existing_topic == topic_id:
            if _clear_stale_active_run(existing, now):
                db.session.commit()
                break
            return existing.to_dict()

    run = AutomationRun(
        rule_id=rule.id,
        status="queued",
        trigger_source=trigger_source,
        event_context=event_context or {},
        result={},
        started_at=now,
    )
    db.session.add(run)
    db.session.commit()
    return run.to_dict()


def enqueue_due_scheduled_rules(now=None):
    from services.automation_dispatcher import dispatch_due_scheduled_rules

    return dispatch_due_scheduled_rules(now=now)


def process_run(run_id, now=None):
    now = now or datetime.utcnow()
    run = (
        AutomationRun.query.filter_by(id=run_id, status="queued")
        .with_for_update(skip_locked=True)
        .first()
    )
    if run is None:
        return None

    run.status = "running"
    run.started_at = now
    result = _execute_run(run, now)
    db.session.commit()
    return result


def process_automation_queue(limit=5):
    now = datetime.utcnow()
    if _clear_stale_active_runs(now):
        db.session.commit()

    runs = (
        AutomationRun.query.filter_by(status="queued")
        .order_by(AutomationRun.id)
        .with_for_update(skip_locked=True)
        .limit(limit)
        .all()
    )
    results = []
    for run in runs:
        run.status = "running"
        run.started_at = now
        results.append(_execute_run(run, now))
    if runs:
        db.session.commit()
    return results


def _execute_run(run, now):
    rule = db.session.get(AutomationRule, run.rule_id)
    if rule is None:
        run.status = "failed"
        run.error = "rule not found"
        run.finished_at = datetime.utcnow()
        _after_event_run_finished(run)
        return run.to_dict()

    activation_error = validate_rule_activation(
        rule,
        trigger_source=run.trigger_source,
    )
    if activation_error:
        run.status = "failed"
        run.error = activation_error
        run.finished_at = datetime.utcnow()
        _after_event_run_finished(run)
        return run.to_dict()

    try:
        result = run_action(rule, run=run)
        run.status = "success"
        run.result = result or {}
        rule.last_run_at = now
    except Exception as error:
        run.status = "failed"
        run.error = str(error)

    run.finished_at = datetime.utcnow()
    _after_event_run_finished(run)
    return run.to_dict()


def _after_event_run_finished(run):
    if run.trigger_source != "event":
        return
    try:
        from flask import current_app

        from services.automation_change_triggers import (
            on_automation_run_finished,
            process_due_change_triggers,
        )

        app = current_app._get_current_object()
        on_automation_run_finished(run, app=app)
        process_due_change_triggers(app=app)
    except RuntimeError:
        pass


def run_due_automations(now=None):
    """Backward-compatible entry point used by the cron script."""
    from services.automation_change_triggers import process_due_change_triggers

    enqueued = enqueue_due_scheduled_rules(now=now)
    processed = process_automation_queue()
    change_trigger_runs = process_due_change_triggers(now=now)
    return {
        "enqueued": enqueued,
        "processed": processed,
        "change_triggers": change_trigger_runs,
    }
