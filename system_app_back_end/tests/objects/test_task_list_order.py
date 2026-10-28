"""Tests for task list order helpers."""

from areas.objects.services.task_list_order import merged_task_ids_after_zone_insert


class _Task:
    def __init__(self, task_id: int, status: str = "active"):
        self.id = task_id
        self.status = status


def test_zone_insert_preserves_other_tasks_canonical_order():
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
    assert merged == [2, 1, 3]


def test_merged_task_ids_after_zone_insert_clamps_insert_index():
    tasks = [_Task(1), _Task(2)]
    merged = merged_task_ids_after_zone_insert(
        tasks,
        _Task(99),
        target_done=False,
        insert_index_in_zone=99,
    )
    assert merged == [1, 2, 99]


def test_reorder_active_tasks_keeps_interleaved_done_siblings_in_order():
    tasks = [_Task(1), _Task(2, "done"), _Task(3), _Task(4, "done"), _Task(5)]
    merged = merged_task_ids_after_zone_insert(
        tasks, tasks[4], target_done=False, insert_index_in_zone=1,
    )
    assert merged == [1, 2, 5, 3, 4]


def test_insert_into_empty_zone_preserves_existing_order():
    tasks = [_Task(1, "done"), _Task(2, "done")]
    assert merged_task_ids_after_zone_insert(
        tasks, _Task(3), target_done=False, insert_index_in_zone=0,
    ) == [1, 2, 3]
