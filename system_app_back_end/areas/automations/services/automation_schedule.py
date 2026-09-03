import calendar
import re
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

PLACEMENTS = ("first", "second", "third", "last")
_FROM_YM = re.compile(r"^(\d{4})-(\d{2})$")


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
    kind = parsed["kind"]
    hour, minute = parsed["hour"], parsed["minute"]
    if kind == "daily":
        return after_local.replace(
            hour=hour, minute=minute, second=0, microsecond=0
        )
    if kind == "weekly":
        if after_local.weekday() not in parsed["weekdays"]:
            return None
        return after_local.replace(
            hour=hour, minute=minute, second=0, microsecond=0
        )
    if parsed["interval"] > 1 and parsed["origin"] is not None:
        if not _in_cycle_month(
            after_local.year, after_local.month, parsed["interval"], parsed["origin"]
        ):
            return None
    for placement, weekday in parsed["slots"]:
        candidate = _monthly_candidate_local(
            after_local.year,
            after_local.month,
            placement,
            weekday,
            hour,
            minute,
            tz,
        )
        if candidate.date() == after_local.date():
            return candidate
    placement, weekday = parsed["slots"][0]
    return _monthly_candidate_local(
        after_local.year,
        after_local.month,
        placement,
        weekday,
        hour,
        minute,
        tz,
    )


def next_run_after(schedule, after_utc, timezone=DEFAULT_AUTOMATION_TIMEZONE):
    if not schedule:
        raise ValueError("schedule is required")

    tz = resolve_timezone(timezone)
    after_local = utc_naive_to_local(after_utc, tz)

    parsed = _parse_schedule(schedule)
    if parsed is None:
        raise ValueError(
            "schedule must be 'daily HH:MM', 'weekly DAY[,DAY] HH:MM', "
            "'monthly PLACEMENT DAY HH:MM', "
            "'monthly PLACEMENT.DAY[,…] HH:MM', "
            "'monthly N … [from YYYY-MM]' (every N months), or "
            "'quarterly INTERVAL PLACEMENT DAY HH:MM'"
        )
    kind = parsed["kind"]
    hour, minute = parsed["hour"], parsed["minute"]
    if kind == "daily":
        candidate = after_local.replace(
            hour=hour, minute=minute, second=0, microsecond=0
        )
        if candidate <= after_local:
            candidate += timedelta(days=1)
        return local_to_utc_naive(candidate)

    if kind == "weekly":
        return local_to_utc_naive(
            _next_weekly_local(after_local, parsed["weekdays"], hour, minute)
        )

    return local_to_utc_naive(
        _next_monthly_local(
            after_local,
            parsed["slots"],
            parsed["interval"],
            parsed["origin"],
            hour,
            minute,
            tz,
        )
    )


def _next_weekly_local(after_local, weekdays, hour, minute):
    clock = after_local.replace(hour=hour, minute=minute, second=0, microsecond=0)
    soonest = None
    for weekday in weekdays:
        candidate = clock + timedelta(days=(weekday - clock.weekday()) % 7)
        if candidate <= after_local:
            candidate += timedelta(days=7)
        if soonest is None or candidate < soonest:
            soonest = candidate
    return soonest


def _next_monthly_local(after_local, slots, interval, origin, hour, minute, tz):
    year, month = after_local.year, after_local.month

    def soonest_in_month(y, m, after):
        future = []
        for placement, weekday in slots:
            candidate = _monthly_candidate_local(
                y, m, placement, weekday, hour, minute, tz
            )
            if candidate > after:
                future.append(candidate)
        return min(future) if future else None

    if origin is not None:
        for _ in range(48):
            if _in_cycle_month(year, month, interval, origin):
                hit = soonest_in_month(year, month, after_local)
                if hit is not None:
                    return hit
            year, month = _add_months(year, month, 1)
        raise ValueError("no monthly occurrence in range")

    hit = soonest_in_month(year, month, after_local)
    if hit is not None:
        return hit
    year, month = _add_months(year, month, interval)
    candidates = [
        _monthly_candidate_local(year, month, placement, weekday, hour, minute, tz)
        for placement, weekday in slots
    ]
    return min(candidates)


def _in_cycle_month(year, month, interval, origin):
    if interval <= 1:
        return True
    origin_year, origin_month = origin
    delta = (year * 12 + month) - (origin_year * 12 + origin_month)
    return delta % interval == 0


def _parse_time(value):
    hour, minute = value.split(":")
    hour, minute = int(hour), int(minute)
    if hour < 0 or hour > 23 or minute < 0 or minute > 59:
        raise ValueError("time must be HH:MM in 24-hour format")
    return hour, minute


def _looks_time(value):
    try:
        _parse_time(value)
        return True
    except (ValueError, IndexError, AttributeError):
        return False


def _take_origin(parts):
    if len(parts) >= 2 and parts[-2].lower() == "from":
        match = _FROM_YM.match(parts[-1])
        if match is None:
            raise ValueError("from must be YYYY-MM")
        year, month = int(match.group(1)), int(match.group(2))
        if month < 1 or month > 12:
            raise ValueError("from month must be 01 to 12")
        return parts[:-2], (year, month)
    return parts, None


def _parse_weekdays(raw):
    weekdays = []
    seen = set()
    for token in raw.split(","):
        token = token.strip().lower()
        if not token:
            continue
        if token not in WEEKDAYS:
            raise ValueError(f"unknown weekday: {token}")
        weekday = WEEKDAYS[token]
        if weekday not in seen:
            seen.add(weekday)
            weekdays.append(weekday)
    return weekdays or [0]


def _parse_placement(raw):
    placement = raw.lower()
    if placement not in PLACEMENTS:
        raise ValueError("monthly placement must be first, second, third, or last")
    return placement


def _parse_month_slots(slot_parts):
    if not slot_parts:
        return [("first", 0)]
    if (
        len(slot_parts) == 2
        and "," not in slot_parts[0]
        and "." not in slot_parts[0]
    ):
        return [
            (
                _parse_placement(slot_parts[0]),
                WEEKDAYS.get(slot_parts[1].lower(), 0),
            )
        ]
    return _parse_compact_slots(slot_parts[0])


def _parse_compact_slots(raw):
    slots = []
    seen = set()
    for token in raw.split(","):
        token = token.strip().lower()
        if not token:
            continue
        if "." in token:
            placement_raw, weekday_raw = token.split(".", 1)
        elif "-" in token:
            placement_raw, weekday_raw = token.split("-", 1)
        else:
            raise ValueError("monthly slot must be placement.weekday")
        slot = (_parse_placement(placement_raw), WEEKDAYS.get(weekday_raw, 0))
        if slot not in seen:
            seen.add(slot)
            slots.append(slot)
    return slots or [("first", 0)]


def _parse_schedule(schedule):
    """kind / interval / weekdays / slots / hour / minute / origin, or None."""
    kind, *parts = schedule.split()
    kind = kind.lower()
    if kind == "daily":
        hour, minute = _parse_time(parts[0] if parts else "00:00")
        return {
            "kind": kind,
            "interval": 1,
            "weekdays": [0],
            "slots": [("first", 0)],
            "hour": hour,
            "minute": minute,
            "origin": None,
        }
    if kind == "weekly":
        parts, _origin = _take_origin(parts)
        if not parts:
            hour, minute = 0, 0
            weekdays = [0]
        elif len(parts) == 1 and _looks_time(parts[0]):
            hour, minute = _parse_time(parts[0])
            weekdays = [0]
        else:
            weekdays = _parse_weekdays(parts[0])
            hour, minute = _parse_time(parts[1] if len(parts) > 1 else "00:00")
        return {
            "kind": kind,
            "interval": 1,
            "weekdays": weekdays,
            "slots": [("first", weekdays[0])],
            "hour": hour,
            "minute": minute,
            "origin": None,
        }
    if kind in ("monthly", "quarterly"):
        parts, origin = _take_origin(parts)
        if kind == "quarterly":
            interval = _parse_month_interval(parts[0] if parts else "3")
            rest = parts[1:]
        elif parts and parts[0].isdigit():
            interval = int(parts[0])
            if interval < 1 or interval > 12:
                raise ValueError("month interval must be between 1 and 12")
            rest = parts[1:]
        else:
            interval = 1
            rest = parts
        if rest and _looks_time(rest[-1]):
            hour, minute = _parse_time(rest[-1])
            slot_parts = rest[:-1]
        else:
            hour, minute = 0, 0
            slot_parts = rest
        slots = _parse_month_slots(slot_parts)
        return {
            "kind": "monthly",
            "interval": interval,
            "weekdays": [slots[0][1]],
            "slots": slots,
            "hour": hour,
            "minute": minute,
            "origin": origin,
        }
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
