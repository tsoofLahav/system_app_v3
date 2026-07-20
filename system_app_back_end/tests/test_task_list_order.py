"""Tests for task list order helpers."""

from services.task_list_order import merged_task_ids_after_zone_insert


class _Task:
    def __init__(self, task_id: int, status: str = "active"):
        self.id = task_id
        self.status = status


def test_merged_task_ids_after_zone_insert_keeps_active_before_done():
    tasks = [
        _Task(1),
        _Task(2, status="done"),
        _Task(3),
    ]
    merged = merged_task_ids_after_zone_insert(
        tasks,
        tasks[0],
        target_done=True,
        insert_index_in_zone=1,
    )
    assert merged == [3, 2, 1]


def test_merged_task_ids_after_zone_insert_clamps_insert_index():
    tasks = [_Task(1), _Task(2)]
    merged = merged_task_ids_after_zone_insert(
        tasks,
        _Task(99),
        target_done=False,
        insert_index_in_zone=99,
    )
    assert merged == [1, 2, 99]
