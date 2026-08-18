import calendar
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

UTC = ZoneInfo("UTC")
DEFAULT_AUTOMATION_TIMEZONE = "Asia/Jerusalem"

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


def resolve_timezone(timezone_name):
    try:
        return ZoneInfo(timezone_name or UTC.key)
    except Exception:
        return UTC


def as_utc_naive(dt):
    """Postgres `timestamptz` comes back aware; the rest of this module is naive UTC."""
    if dt is None:
        return None
    if dt.tzinfo is None:
        return dt
    return dt.astimezone(UTC).replace(tzinfo=None)


def utc_naive_to_local(dt_utc_naive, tz):
    return as_utc_naive(dt_utc_naive).replace(tzinfo=UTC).astimezone(tz)


def local_to_utc_naive(dt_local):
    return dt_local.astimezone(UTC).replace(tzinfo=None)


def plan_tick(*, schedule, timezone, now_utc, next_run_at):
    """What the clock should do with one automation this minute.

    Returns `(action, next_run_at)` where action is:

    - `"run"` — it is due; the new `next_run_at` is already computed
    - `"arm"` — first sight of it, so record when it should fire and wait.
      Without this a `daily 08:00` created at 10:00 would run the moment it
      was saved, which is not what "daily at eight" means to anyone
    - `"skip"` — not due, or the schedule string is not one we can read

    Pure so the timing rules can be tested without a database or a clock.
    """
    now_utc = as_utc_naive(now_utc)
    next_run_at = as_utc_naive(next_run_at)
    if not (schedule or "").strip():
        return "skip", next_run_at

    try:
        if next_run_at is None:
            return "arm", next_run_after(schedule, now_utc, timezone)
        if next_run_at <= now_utc:
            return "run", next_run_after(schedule, now_utc, timezone)
    except ValueError:
        return "skip", next_run_at
    return "skip", next_run_at


def next_run_after(schedule, after_utc, timezone=UTC.key):
    if not schedule:
        raise ValueError("schedule is required")

    tz = resolve_timezone(timezone)
    after_local = utc_naive_to_local(after_utc, tz)

    kind, *parts = schedule.split()
    kind = kind.lower()
    if kind == "daily":
        hour, minute = _parse_time(parts[0] if parts else "00:00")
        candidate = after_local.replace(
            hour=hour, minute=minute, second=0, microsecond=0
        )
        if candidate <= after_local:
            candidate += timedelta(days=1)
        return local_to_utc_naive(candidate)

    if kind == "weekly":
        weekday = WEEKDAYS.get((parts[0] if parts else "mon").lower(), 0)
        hour, minute = _parse_time(parts[1] if len(parts) > 1 else "00:00")
        candidate = after_local.replace(
            hour=hour, minute=minute, second=0, microsecond=0
        )
        days = (weekday - candidate.weekday()) % 7
        candidate += timedelta(days=days)
        if candidate <= after_local:
            candidate += timedelta(days=7)
        return local_to_utc_naive(candidate)

    if kind == "monthly":
        placement = (parts[0] if parts else "first").lower()
        weekday = WEEKDAYS.get((parts[1] if len(parts) > 1 else "mon").lower(), 0)
        hour, minute = _parse_time(parts[2] if len(parts) > 2 else "00:00")
        candidate = _monthly_candidate_local(
            after_local.year,
            after_local.month,
            placement,
            weekday,
            hour,
            minute,
            tz,
        )
        if candidate <= after_local:
            year, month = _next_month(after_local.year, after_local.month)
            candidate = _monthly_candidate_local(
                year, month, placement, weekday, hour, minute, tz
            )
        return local_to_utc_naive(candidate)

    if kind == "quarterly":
        interval = _parse_month_interval(parts[0] if parts else "3")
        placement = (parts[1] if len(parts) > 1 else "first").lower()
        weekday = WEEKDAYS.get((parts[2] if len(parts) > 2 else "mon").lower(), 0)
        hour, minute = _parse_time(parts[3] if len(parts) > 3 else "00:00")
        candidate = _interval_month_candidate_local(
            after_local,
            interval,
            placement,
            weekday,
            hour,
            minute,
            tz,
        )
        return local_to_utc_naive(candidate)

    raise ValueError(
        "schedule must be 'daily HH:MM', 'weekly DAY HH:MM', "
        "'monthly PLACEMENT DAY HH:MM', or "
        "'quarterly INTERVAL PLACEMENT DAY HH:MM'"
    )


def _parse_time(value):
    hour, minute = value.split(":")
    hour, minute = int(hour), int(minute)
    if hour < 0 or hour > 23 or minute < 0 or minute > 59:
        raise ValueError("time must be HH:MM in 24-hour format")
    return hour, minute


def _parse_month_interval(value):
    interval = int(value)
    if interval not in {3, 4}:
        raise ValueError("quarterly interval must be 3 or 4 months")
    return interval


def _monthly_candidate_local(year, month, placement, weekday, hour, minute, tz):
    if placement == "last":
        last_day = calendar.monthrange(year, month)[1]
        last_weekday = datetime(year, month, last_day, tzinfo=tz).weekday()
        day = last_day - ((last_weekday - weekday) % 7)
    else:
        occurrence = {"first": 1, "second": 2, "third": 3}.get(placement)
        if occurrence is None:
            raise ValueError("monthly placement must be first, second, third, or last")
        first_weekday = datetime(year, month, 1, tzinfo=tz).weekday()
        day = 1 + ((weekday - first_weekday) % 7) + ((occurrence - 1) * 7)

    return datetime(year, month, day, hour, minute, tzinfo=tz)


def _interval_month_candidate_local(
    after_local,
    interval,
    placement,
    weekday,
    hour,
    minute,
    tz,
):
    year, month = after_local.year, after_local.month
    for _ in range(0, 24):
        if (month - 1) % interval == 0:
            candidate = _monthly_candidate_local(
                year,
                month,
                placement,
                weekday,
                hour,
                minute,
                tz,
            )
            if candidate > after_local:
                return candidate
        year, month = _next_month(year, month)
    raise ValueError("could not find next quarterly candidate")


def _next_month(year, month):
    if month == 12:
        return year + 1, 1
    return year, month + 1
