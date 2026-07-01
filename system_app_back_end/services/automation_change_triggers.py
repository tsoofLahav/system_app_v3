"""Debounced change triggers for event-driven automations.

Coalesces rapid domain changes (e.g. file edits) into idle-windowed runs and
schedules a follow-up when changes arrive while a run is already active.
"""

from __future__ import annotations

import threading
from datetime import datetime, timedelta

from models import AutomationChangeTrigger, AutomationRule, AutomationRun, db
from services.automation_definitions import ChangeTriggerConfig, get_definition
from services.automation_params import normalize_params
from services.automation_runner import ACTIVE_RUN_STATUSES, enqueue_run, kick_run_async

_watchers: dict[tuple[int, str], threading.Timer] = {}
_watchers_lock = threading.Lock()


def change_trigger_config_for_rule(rule: AutomationRule) -> ChangeTriggerConfig | None:
    definition = get_definition(rule.key, rule.action_type)
    if definition is None or "event" not in definition.activations:
        return None

    base = definition.change_trigger
    if base is not None and not base.enabled:
        return None

    params = normalize_params(rule.params, rule.key, rule.action_type)
    override = params.get("change_trigger") or {}
    if override.get("enabled") is False:
        return None

    defaults = base or ChangeTriggerConfig()
    idle_seconds = override.get("idle_seconds", defaults.idle_seconds)
    coalesce = override.get("coalesce_during_run", defaults.coalesce_during_run)
    return ChangeTriggerConfig(
        enabled=True,
        idle_seconds=max(1, int(idle_seconds)),
        coalesce_during_run=bool(coalesce),
    )


def dedupe_key_for_event(event_context: dict) -> str:
    topic_id = event_context.get("topic_id")
    if topic_id is not None:
        return f"topic:{int(topic_id)}"
    file_id = event_context.get("file_id")
    if file_id is not None:
        return f"file:{int(file_id)}"
    return "global"


def record_change_event(rule: AutomationRule, event_context: dict, app=None) -> None:
    """Record a domain change and (re)start the idle debounce window."""
    config = change_trigger_config_for_rule(rule)
    if config is None:
        return

    now = datetime.utcnow()
    dedupe_key = dedupe_key_for_event(event_context)
    topic_id = event_context.get("topic_id")
    active = _has_active_run(rule.id, topic_id)

    row = AutomationChangeTrigger.query.filter_by(
        rule_id=rule.id,
        dedupe_key=dedupe_key,
    ).first()
    if row is None:
        row = AutomationChangeTrigger(
            rule_id=rule.id,
            dedupe_key=dedupe_key,
            event_context=dict(event_context),
            fire_at=now + timedelta(seconds=config.idle_seconds),
            dirty=False,
        )
        db.session.add(row)
    else:
        row.event_context = _merge_event_context(row.event_context, event_context)
        row.fire_at = now + timedelta(seconds=config.idle_seconds)
        row.updated_at = now

    if active and config.coalesce_during_run:
        row.dirty = True

    db.session.commit()
    _schedule_watch(app, rule.id, dedupe_key, config.idle_seconds)


def process_due_change_triggers(now=None, app=None, limit=50) -> list[int]:
    """Fire change triggers whose idle window has elapsed."""
    now = now or datetime.utcnow()
    rows = (
        AutomationChangeTrigger.query.filter(AutomationChangeTrigger.fire_at <= now)
        .order_by(AutomationChangeTrigger.fire_at, AutomationChangeTrigger.id)
        .limit(limit)
        .all()
    )
    run_ids = []
    for row in rows:
        run_id = _try_fire_change_trigger(row, app=app, now=now)
        if run_id is not None:
            run_ids.append(run_id)
    return run_ids


def on_automation_run_finished(run: AutomationRun, app=None) -> None:
    """Schedule a follow-up when changes accumulated during an active run."""
    if run.trigger_source != "event":
        return

    topic_id = (run.event_context or {}).get("topic_id")
    dedupe_key = dedupe_key_for_event(run.event_context or {})
    row = AutomationChangeTrigger.query.filter_by(
        rule_id=run.rule_id,
        dedupe_key=dedupe_key,
    ).first()
    if row is None or not row.dirty:
        return

    rule = db.session.get(AutomationRule, run.rule_id)
    if rule is None:
        return
    config = change_trigger_config_for_rule(rule)
    if config is None:
        return

    row.dirty = False
    row.updated_at = datetime.utcnow()
    db.session.commit()

    now = datetime.utcnow()
    delay_seconds = max(0.0, (row.fire_at - now).total_seconds())
    if delay_seconds <= 0:
        run_id = _try_fire_change_trigger(row, app=app, now=now)
        if run_id is not None:
            return
        delay_seconds = float(config.idle_seconds)

    _schedule_watch(app, run.rule_id, dedupe_key, delay_seconds)


def _try_fire_change_trigger(
    row: AutomationChangeTrigger,
    *,
    app=None,
    now=None,
) -> int | None:
    now = now or datetime.utcnow()
    if row.fire_at > now:
        return None

    rule = db.session.get(AutomationRule, row.rule_id)
    if rule is None or not rule.enabled:
        db.session.delete(row)
        db.session.commit()
        return None

    topic_id = (row.event_context or {}).get("topic_id")
    if _has_active_run(rule.id, topic_id):
        row.dirty = True
        row.updated_at = now
        db.session.commit()
        return None

    run_dict = enqueue_run(rule, "event", dict(row.event_context or {}))
    db.session.delete(row)
    db.session.commit()

    run_id = int(run_dict["id"]) if run_dict else None
    if run_id is not None and app is not None:
        kick_run_async(app, run_id)
    return run_id


def _has_active_run(rule_id: int, topic_id) -> bool:
    active_runs = (
        AutomationRun.query.filter_by(rule_id=rule_id)
        .filter(AutomationRun.status.in_(ACTIVE_RUN_STATUSES))
        .all()
    )
    for existing in active_runs:
        existing_topic = (existing.event_context or {}).get("topic_id")
        if topic_id is None and existing_topic is None:
            return True
        if topic_id is not None and existing_topic == topic_id:
            return True
    return False


def _merge_event_context(existing: dict | None, incoming: dict) -> dict:
    merged = dict(existing or {})
    merged.update(incoming)
    return merged


def _schedule_watch(app, rule_id: int, dedupe_key: str, delay_seconds: float) -> None:
    if app is None:
        return

    key = (rule_id, dedupe_key)
    delay_seconds = max(0.05, float(delay_seconds))

    with _watchers_lock:
        existing = _watchers.pop(key, None)
        if existing is not None:
            existing.cancel()

        def fire():
            with _watchers_lock:
                _watchers.pop(key, None)
            with app.app_context():
                row = AutomationChangeTrigger.query.filter_by(
                    rule_id=rule_id,
                    dedupe_key=dedupe_key,
                ).first()
                if row is None:
                    return
                _try_fire_change_trigger(row, app=app)

        timer = threading.Timer(delay_seconds, fire)
        timer.daemon = True
        _watchers[key] = timer
        timer.start()
