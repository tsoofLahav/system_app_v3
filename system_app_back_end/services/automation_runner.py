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


def run_due_automations(now=None):
    now = now or datetime.utcnow()
    rules = (
        AutomationRule.query.filter_by(enabled=True)
        .filter(AutomationRule.next_run_at <= now)
        .order_by(AutomationRule.next_run_at, AutomationRule.id)
        .all()
    )
    results = []
    for rule in rules:
        results.append(run_rule(rule, now=now))
    return results


def run_rule(rule, now=None):
    now = now or datetime.utcnow()
    run = AutomationRun(rule_id=rule.id, status="running", started_at=now)
    db.session.add(run)
    db.session.flush()
    try:
        result = run_action(rule)
        run.status = "success"
        run.result = result or {}
        rule.last_run_at = now
        rule.next_run_at = next_run_after(rule.schedule, now)
    except Exception as error:
        db.session.rollback()
        run = AutomationRun(
            rule_id=rule.id,
            status="failed",
            started_at=now,
            finished_at=datetime.utcnow(),
            error=str(error),
        )
        db.session.add(run)
        db.session.commit()
        return run.to_dict()

    run.finished_at = datetime.utcnow()
    db.session.commit()
    return run.to_dict()


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
    raise ValueError("schedule must be 'daily HH:MM' or 'weekly DAY HH:MM'")


def _parse_time(value):
    hour, minute = value.split(":")
    return int(hour), int(minute)
