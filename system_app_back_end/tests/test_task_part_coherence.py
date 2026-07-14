"""Tests for task/part coherence helpers."""

from services.unit_mapper import _tasks_by_id_for_part_blocks


class _Block:
    def __init__(self, block_id: int, block_type: str):
        self.id = block_id
        self.type = block_type


def test_tasks_by_id_for_part_blocks_falls_back_without_task_list():
    blocks = [_Block(11, "task")]

    result = _tasks_by_id_for_part_blocks(blocks, {5: "Legacy"})

    assert result == {5: "Legacy"}
