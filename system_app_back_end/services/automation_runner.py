import calendar
import threading
from datetime import datetime, timedelta

from models import AutomationRule, AutomationRun, db
from services.automation_actions import run_action


WEEKDAYS = {
    "mon": 0,
    "monday": 0,
    "tue": 1,
    "tuesday": 1,
    "wed": 2,
    "wednesday": 2,
    "thu": 3,
    "thursday": 3,
    "fri": 4,
    "friday": 4,
    "sat": 5,
    "saturday": 5,
    "sun": 6,
    "sunday": 6,
}

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
    existing = (
        AutomationRun.query.filter_by(rule_id=rule.id)
        .filter(AutomationRun.status.in_(ACTIVE_RUN_STATUSES))
        .first()
    )
    if existing is not None:
        if _clear_stale_active_run(existing, now):
            db.session.commit()
        else:
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
    now = now or datetime.utcnow()
    rules = (
        AutomationRule.query.filter_by(enabled=True, trigger_type="schedule")
        .filter(AutomationRule.next_run_at <= now)
        .order_by(AutomationRule.next_run_at, AutomationRule.id)
        .all()
    )
    results = []
    for rule in rules:
        results.append(enqueue_run(rule, trigger_source="schedule"))
    return results


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
        return run.to_dict()

    try:
        result = run_action(rule)
        run.status = "success"
        run.result = result or {}
        rule.last_run_at = now
        if rule.trigger_type == "schedule" and rule.schedule:
            rule.next_run_at = next_run_after(rule.schedule, now)
    except Exception as error:
        run.status = "failed"
        run.error = str(error)

    run.finished_at = datetime.utcnow()
    return run.to_dict()


def run_due_automations(now=None):
    """Backward-compatible entry point used by the cron script."""
    enqueued = enqueue_due_scheduled_rules(now=now)
    processed = process_automation_queue()
    return {"enqueued": enqueued, "processed": processed}


def next_run_after(schedule, after):
    kind, *parts = schedule.split()
    kind = kind.lower()
    if kind == "daily":
        hour, minute = _parse_time(parts[0] if parts else "00:00")
        candidate = after.replace(hour=hour, minute=minute, second=0, microsecond=0)
        if candidate <= after:
            candidate += timedelta(days=1)
        return candidate
    if kind == "weekly":
        weekday = WEEKDAYS.get((parts[0] if parts else "mon").lower(), 0)
        hour, minute = _parse_time(parts[1] if len(parts) > 1 else "00:00")
        candidate = after.replace(hour=hour, minute=minute, second=0, microsecond=0)
        days = (weekday - candidate.weekday()) % 7
        candidate += timedelta(days=days)
        if candidate <= after:
            candidate += timedelta(days=7)
        return candidate
    if kind == "monthly":
        placement = (parts[0] if parts else "first").lower()
        weekday = WEEKDAYS.get((parts[1] if len(parts) > 1 else "mon").lower(), 0)
        hour, minute = _parse_time(parts[2] if len(parts) > 2 else "00:00")
        candidate = _monthly_candidate(
            after.year, after.month, placement, weekday, hour, minute
        )
        if candidate <= after:
            year, month = _next_month(after.year, after.month)
            candidate = _monthly_candidate(year, month, placement, weekday, hour, minute)
        return candidate
    raise ValueError(
        "schedule must be 'daily HH:MM', 'weekly DAY HH:MM', "
        "or 'monthly PLACEMENT DAY HH:MM'"
    )


def _parse_time(value):
    hour, minute = value.split(":")
    hour, minute = int(hour), int(minute)
    if hour < 0 or hour > 23 or minute < 0 or minute > 59:
        raise ValueError("time must be HH:MM in 24-hour format")
    return hour, minute


def _monthly_candidate(year, month, placement, weekday, hour, minute):
    if placement == "last":
        last_day = calendar.monthrange(year, month)[1]
        last_weekday = datetime(year, month, last_day).weekday()
        day = last_day - ((last_weekday - weekday) % 7)
    else:
        occurrence = {"first": 1, "second": 2, "third": 3}.get(placement)
        if occurrence is None:
            raise ValueError("monthly placement must be first, second, third, or last")
        first_weekday = datetime(year, month, 1).weekday()
        day = 1 + ((weekday - first_weekday) % 7) + ((occurrence - 1) * 7)

    return datetime(year, month, day, hour, minute)


def _next_month(year, month):
    if month == 12:
        return year + 1, 1
    return year, month + 1
