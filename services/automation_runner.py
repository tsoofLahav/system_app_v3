import calendar
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
