"""Tests for task view reorder."""

from services.task_view_order import reorder_task_views


def test_reorder_task_views_is_importable():
    assert callable(reorder_task_views)
