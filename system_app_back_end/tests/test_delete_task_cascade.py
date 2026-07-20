"""Tests for task delete cascade list order compaction."""

from services.delete_cascade import delete_task_cascade


def test_delete_task_cascade_is_importable():
    assert callable(delete_task_cascade)
