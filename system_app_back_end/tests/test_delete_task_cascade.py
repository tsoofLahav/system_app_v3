"""Tests for task delete cascade."""

from services.delete_cascade import (
    _list_block_id_for_task,
    _normalize_task_block_id,
    delete_task_cascade,
)


def test_delete_task_cascade_is_importable():
    assert callable(delete_task_cascade)


def test_list_block_id_from_task_list_block():
    class Block:
        id = 10
        type = "task_list"
        file_id = 1

    class Task:
        block_id = 10

    assert _list_block_id_for_task(Task()) == 10


def test_normalize_task_block_id_repoints_row_block(monkeypatch):
    list_block = type("Block", (), {"id": 10, "type": "task_list", "file_id": 1})()
    row_block = type("Block", (), {"id": 20, "type": "task", "file_id": 1})()
    task = type("Task", (), {"block_id": 20})()

    def fake_get(model, block_id):
        if block_id == 20:
            return row_block
        if block_id == 10:
            return list_block
        return None

    monkeypatch.setattr(
        "services.delete_cascade.db.session.get",
        fake_get,
    )
    monkeypatch.setattr(
        "services.delete_cascade._list_block_id_for_task",
        lambda _task: 10,
    )

    _normalize_task_block_id(task)
    assert task.block_id == 10
