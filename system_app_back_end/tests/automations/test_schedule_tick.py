"""When the clock should run an automation, and when it must not.

The old script ran every enabled row every minute. These are the rules that
replace it.
"""

from datetime import datetime, timezone

from types import SimpleNamespace

from areas.automations.services.automation_schedule import (
    DEFAULT_AUTOMATION_TIMEZONE,
    next_run_after,
    normalize_stored_timezone,
    plan_tick,
    resolve_timezone,
    wall_clock,
)

NOW = datetime(2026, 8, 18, 9, 0)


def test_a_new_automation_is_armed_not_run():
    """`daily 08:00` saved at 09:00 means tomorrow at eight, not right now."""
    action, next_run_at = plan_tick(
        schedule="daily 08:00", timezone="UTC", now_utc=NOW, next_run_at=None
    )
    assert action == "arm"
    assert next_run_at == datetime(2026, 8, 19, 8, 0)


def test_it_runs_once_it_is_due():
    action, next_run_at = plan_tick(
        schedule="daily 08:00",
        timezone="UTC",
        now_utc=NOW,
        next_run_at=datetime(2026, 8, 18, 8, 0),
    )
    assert action == "run"
    assert next_run_at == datetime(2026, 8, 19, 8, 0)


def test_it_stays_put_until_then():
    action, next_run_at = plan_tick(
        schedule="daily 08:00",
        timezone="UTC",
        now_utc=NOW,
        next_run_at=datetime(2026, 8, 19, 8, 0),
    )
    assert action == "skip"
    assert next_run_at == datetime(2026, 8, 19, 8, 0)


def test_no_schedule_never_fires():
    """The bug that made saved actions run 1,440 times a day."""
    for schedule in (None, "", "   "):
        assert plan_tick(
            schedule=schedule, timezone="UTC", now_utc=NOW, next_run_at=None
        ) == ("skip", None)


def test_an_unreadable_schedule_is_skipped_not_raised():
    """One typo must not stop the other automations from running."""
    action, _ = plan_tick(
        schedule="0 8 * * *", timezone="UTC", now_utc=NOW, next_run_at=None
    )
    assert action == "skip"


def test_aware_and_naive_datetimes_can_be_compared():
    """Postgres timestamptz vs datetime.utcnow() used to crash the cron."""
    action, next_run_at = plan_tick(
        schedule="daily 08:00",
        timezone="UTC",
        now_utc=NOW,
        next_run_at=datetime(2026, 8, 18, 8, 0, tzinfo=timezone.utc),
    )
    assert action == "run"
    assert next_run_at == datetime(2026, 8, 19, 8, 0)


def test_missing_timezone_is_israel():
    assert DEFAULT_AUTOMATION_TIMEZONE == "Asia/Jerusalem"
    assert resolve_timezone(None).key == "Asia/Jerusalem"
    assert resolve_timezone("").key == "Asia/Jerusalem"


def test_legacy_utc_rows_rearm_on_israel():
    row = SimpleNamespace(timezone="UTC", next_run_at=datetime(2026, 8, 19, 8, 0))
    assert normalize_stored_timezone(row) is True
    assert row.timezone == "Asia/Jerusalem"
    assert row.next_run_at is None
    assert normalize_stored_timezone(row) is False


def test_wall_clock_is_israel_not_utc():
    # 22:30 UTC on Tuesday is already Wednesday 01:30 in Israel (UTC+3).
    utc = datetime(2026, 8, 18, 22, 30)
    local = wall_clock(utc)
    assert local.day == 19
    assert local.hour == 1


def test_the_timezone_is_the_users_not_utc():
    # 08:00 in Jerusalem (UTC+3) is 05:00 UTC.
    assert next_run_after("daily 08:00", NOW, "Asia/Jerusalem") == datetime(
        2026, 8, 19, 5, 0
    )


def test_first_sight_during_the_due_minute_still_runs():
    """Saving `weekly tue 13:10` at 13:10:04 used to arm next Tuesday."""
    now = datetime(2026, 8, 18, 10, 10, 4)
    action, next_run_at = plan_tick(
        schedule="weekly tue 13:10",
        timezone="Asia/Jerusalem",
        now_utc=now,
        next_run_at=None,
    )
    assert action == "run"
    assert next_run_at == datetime(2026, 8, 25, 10, 10)


def test_every_three_months_skips_the_months_in_between():
    """`monthly 3 last fri 08:00` after August's slot is November, not September."""
    now = datetime(2026, 8, 18, 9, 0)
    assert next_run_after("monthly 3 last fri 08:00", now, "UTC") == datetime(
        2026, 8, 28, 8, 0
    )
    after = datetime(2026, 8, 28, 9, 0)
    assert next_run_after("monthly 3 last fri 08:00", after, "UTC") == datetime(
        2026, 11, 27, 8, 0
    )


def test_plain_monthly_is_still_the_next_month():
    now = datetime(2026, 8, 28, 9, 0)
    assert next_run_after("monthly last fri 08:00", now, "UTC") == datetime(
        2026, 9, 25, 8, 0
    )
