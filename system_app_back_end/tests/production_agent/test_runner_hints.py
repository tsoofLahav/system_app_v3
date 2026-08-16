"""The agent has no clock — the run must hand it one."""

from areas.production_agent.services.runner import _with_time_hints


def test_time_hints_added_when_client_sent_none():
    hints = _with_time_hints({"focused_file_id": 12})

    assert hints["focused_file_id"] == 12
    # YYYY-MM-DD, a weekday name, and an offset-aware timestamp.
    assert len(hints["today"]) == 10 and hints["today"].count("-") == 2
    assert hints["weekday"].isalpha()
    assert hints["now"].startswith(hints["today"])
    assert hints["now"].endswith("+00:00")


def test_client_local_day_wins_over_server_utc():
    """The user's local date is the one they mean, even when UTC has moved on."""
    hints = _with_time_hints(
        {
            "today": "2026-08-16",
            "weekday": "Sunday",
            "now": "2026-08-16T23:40:00+03:00",
        }
    )

    assert hints["today"] == "2026-08-16"
    assert hints["now"] == "2026-08-16T23:40:00+03:00"
