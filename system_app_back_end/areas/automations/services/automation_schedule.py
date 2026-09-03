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
        return ZoneInfo(timezone_name or DEFAULT_AUTOMATION_TIMEZONE)
    except Exception:
        return ZoneInfo(DEFAULT_AUTOMATION_TIMEZONE)


def is_legacy_utc(timezone_name):
    return not (timezone_name or "").strip() or timezone_name.strip() == "UTC"


def normalize_stored_timezone(automation) -> bool:
    """Old rows defaulted to UTC. The app clock is Asia/Jerusalem."""
    if not is_legacy_utc(getattr(automation, "timezone", None)):
        return False
    automation.timezone = DEFAULT_AUTOMATION_TIMEZONE
    automation.next_run_at = None
    return True


def wall_clock(now_utc, timezone_name=None):
    """UTC instant → wall time in the automation timezone (Israel by default)."""
    tz = resolve_timezone(timezone_name or DEFAULT_AUTOMATION_TIMEZONE)
    naive = as_utc_naive(now_utc)
    if naive is None:
        naive = datetime.utcnow()
    return utc_naive_to_local(naive, tz)


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
      was saved, which is not what "daily at eight" means to anyone.
      First sight *during* that 08:00 minute still runs — otherwise a save
      at 08:00:04 jumps to tomorrow and today's slot never happens.
    - `"skip"` — not due, or the schedule string is not one we can read

    Pure so the timing rules can be tested without a database or a clock.
    """
    now_utc = as_utc_naive(now_utc)
    next_run_at = as_utc_naive(next_run_at)
    if not (schedule or "").strip():
        return "skip", next_run_at

    try:
        if next_run_at is None:
            planned = next_run_after(schedule, now_utc, timezone)
            # Saving `weekly tue 13:10` at 13:10:04 used to arm next week,
            # so the slot the user was aiming at never ran.
            if in_current_slot(schedule, now_utc, timezone):
                return "run", planned
            return "arm", planned
        if next_run_at <= now_utc:
            return "run", next_run_after(schedule, now_utc, timezone)
    except ValueError:
        return "skip", next_run_at
    return "skip", next_run_at


SLOT_GRACE = timedelta(seconds=90)


def in_current_slot(schedule, now_utc, timezone=DEFAULT_AUTOMATION_TIMEZONE):
    """True when local time is in this occurrence's minute (plus a short grace)."""
    tz = resolve_timezone(timezone)
    now_local = utc_naive_to_local(now_utc, tz)
    slot = _this_occurrence_local(schedule, now_local, tz)
    if slot is None:
        return False
    return slot <= now_local < slot + SLOT_GRACE


def _this_occurrence_local(schedule, after_local, tz):
    parsed = _parse_schedule(schedule)
    if parsed is None:
        return None
    kind, _interval, placement, weekday, hour, minute = parsed
    if kind == "daily":
        return after_local.replace(
            hour=hour, minute=minute, second=0, microsecond=0
        )
    if kind == "weekly":
        candidate = after_local.replace(
            hour=hour, minute=minute, second=0, microsecond=0
        )
        days = (weekday - candidate.weekday()) % 7
        return candidate + timedelta(days=days)
    candidate = _monthly_candidate_local(
        after_local.year,
        after_local.month,
        placement,
        weekday,
        hour,
        minute,
        tz,
    )
    return candidate


def next_run_after(schedule, after_utc, timezone=DEFAULT_AUTOMATION_TIMEZONE):
    if not schedule:
        raise ValueError("schedule is required")

    tz = resolve_timezone(timezone)
    after_local = utc_naive_to_local(after_utc, tz)

    parsed = _parse_schedule(schedule)
    if parsed is None:
        raise ValueError(
            "schedule must be 'daily HH:MM', 'weekly DAY HH:MM', "
            "'monthly PLACEMENT DAY HH:MM', "
            "'monthly N PLACEMENT DAY HH:MM' (every N months), or "
            "'quarterly INTERVAL PLACEMENT DAY HH:MM'"
        )
    kind, interval, placement, weekday, hour, minute = parsed
    if kind == "daily":
        candidate = after_local.replace(
            hour=hour, minute=minute, second=0, microsecond=0
        )
        if candidate <= after_local:
            candidate += timedelta(days=1)
        return local_to_utc_naive(candidate)

    if kind == "weekly":
        candidate = after_local.replace(
            hour=hour, minute=minute, second=0, microsecond=0
        )
        days = (weekday - candidate.weekday()) % 7
        candidate += timedelta(days=days)
        if candidate <= after_local:
            candidate += timedelta(days=7)
        return local_to_utc_naive(candidate)

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
        year, month = _add_months(after_local.year, after_local.month, interval)
        candidate = _monthly_candidate_local(
            year, month, placement, weekday, hour, minute, tz
        )
    return local_to_utc_naive(candidate)


def _parse_time(value):
    hour, minute = value.split(":")
    hour, minute = int(hour), int(minute)
    if hour < 0 or hour > 23 or minute < 0 or minute > 59:
        raise ValueError("time must be HH:MM in 24-hour format")
    return hour, minute


def _parse_schedule(schedule):
    """(kind, interval, placement, weekday, hour, minute) or None."""
    kind, *parts = schedule.split()
    kind = kind.lower()
    if kind == "daily":
        hour, minute = _parse_time(parts[0] if parts else "00:00")
        return kind, 1, "first", 0, hour, minute
    if kind == "weekly":
        weekday = WEEKDAYS.get((parts[0] if parts else "mon").lower(), 0)
        hour, minute = _parse_time(parts[1] if len(parts) > 1 else "00:00")
        return kind, 1, "first", weekday, hour, minute
    if kind == "monthly":
        if parts and parts[0].isdigit():
            interval = int(parts[0])
            rest = parts[1:]
        else:
            interval = 1
            rest = parts
        if interval < 1 or interval > 12:
            raise ValueError("month interval must be between 1 and 12")
        placement = (rest[0] if rest else "first").lower()
        weekday = WEEKDAYS.get((rest[1] if len(rest) > 1 else "mon").lower(), 0)
        hour, minute = _parse_time(rest[2] if len(rest) > 2 else "00:00")
        return "monthly", interval, placement, weekday, hour, minute
    if kind == "quarterly":
        interval = _parse_month_interval(parts[0] if parts else "3")
        placement = (parts[1] if len(parts) > 1 else "first").lower()
        weekday = WEEKDAYS.get((parts[2] if len(parts) > 2 else "mon").lower(), 0)
        hour, minute = _parse_time(parts[3] if len(parts) > 3 else "00:00")
        return "monthly", interval, placement, weekday, hour, minute
    return None


def _parse_month_interval(value):
    interval = int(value)
    if interval < 2 or interval > 12:
        raise ValueError("quarterly interval must be 2 to 12 months")
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


def _add_months(year, month, n):
    month += n
    year += (month - 1) // 12
    month = (month - 1) % 12 + 1
    return year, month
