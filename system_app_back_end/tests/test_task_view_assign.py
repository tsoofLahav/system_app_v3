"""Tests for single-view task assignment."""

from services.task_view_assign import VIEW_PRIORITY, view_priority


def test_view_priority_order():
    assert view_priority("daily") < view_priority("weekly")
    assert view_priority("weekly") < view_priority("monthly")
    assert view_priority("unknown") >= view_priority("missions")


def test_view_priority_matches_registry_order():
    assert list(VIEW_PRIORITY) == [
        "daily",
        "weekly",
        "monthly",
        "quarterly",
        "arrangements",
        "missions",
    ]
