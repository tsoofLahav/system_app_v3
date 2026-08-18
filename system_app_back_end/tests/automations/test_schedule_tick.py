"""When the clock should run an automation, and when it must not.

The old script ran every enabled row every minute. These are the rules that
replace it.
"""

from datetime import datetime, timezone

from areas.automations.services.automation_schedule import next_run_after, plan_tick

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


def test_the_timezone_is_the_users_not_utc():
    # 08:00 in Jerusalem (UTC+3) is 05:00 UTC.
    assert next_run_after("daily 08:00", NOW, "Asia/Jerusalem") == datetime(
        2026, 8, 19, 5, 0
    )
