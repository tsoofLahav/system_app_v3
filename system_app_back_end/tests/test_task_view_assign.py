"""Tests for single-view task assignment."""

import inspect

from services.task_view_assign import VIEW_PRIORITY, assign_task_view, view_priority


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


def test_assign_task_view_accepts_order_index():
    params = inspect.signature(assign_task_view).parameters
    assert "order_index" in params
    assert params["order_index"].default is None
