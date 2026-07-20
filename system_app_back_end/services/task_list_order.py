"""Task order within a task_list block (list_order_index on tasks)."""

from __future__ import annotations

from sqlalchemy import case

from models import Block, Task, db


def _active_tasks_query():
    return Task.query.filter(Task.archived_at.is_(None))


def _list_block_or_error(block_id: int) -> Block:
    block = db.session.get(Block, block_id)
    if block is None or block.type != "task_list":
        raise ValueError("block must be a task_list")
    return block


def next_list_order_index(block_id: int) -> int:
    max_order = (
        db.session.query(db.func.max(Task.list_order_index))
        .filter(Task.block_id == block_id)
        .scalar()
    )
    return (max_order if max_order is not None else -1) + 1


def tasks_for_list_block_query(block_id: int):
    return (
        _active_tasks_query()
        .filter(Task.block_id == block_id)
        .order_by(
            case((Task.status == "done", 1), else_=0),
            Task.list_order_index,
            Task.id,
        )
    )


def tasks_for_list_block(block_id: int) -> list[Task]:
    return tasks_for_list_block_query(block_id).all()


def apply_list_task_order(block_id: int, ordered_task_ids: list[int]) -> list[Task]:
    """Set list_order_index 0..n-1 for tasks in ordered_task_ids (active then done)."""
    if not ordered_task_ids:
        return []
    if len(set(ordered_task_ids)) != len(ordered_task_ids):
        raise ValueError("duplicate task ids")

    tasks = (
        _active_tasks_query()
        .filter(Task.block_id == block_id, Task.id.in_(ordered_task_ids))
        .all()
    )
    if len(tasks) != len(ordered_task_ids):
        raise ValueError("task ids must belong to list block")

    by_id = {task.id: task for task in tasks}
    for index, task_id in enumerate(ordered_task_ids):
        by_id[task_id].list_order_index = index

    db.session.flush()
    return tasks_for_list_block(block_id)


def merged_task_ids_after_zone_insert(
    list_tasks: list[Task],
    task: Task,
    *,
    target_done: bool,
    insert_index_in_zone: int,
) -> list[int]:
    active = [t for t in list_tasks if t.status != "done" and t.id != task.id]
    done = [t for t in list_tasks if t.status == "done" and t.id != task.id]
    zone = done if target_done else active
    index = max(0, min(insert_index_in_zone, len(zone)))
    zone.insert(index, task)
    return [t.id for t in active] + [t.id for t in done]


def reorder_tasks_in_list_block(block_id: int, ordered_task_ids: list[int]) -> list[Task]:
    _list_block_or_error(block_id)
    return apply_list_task_order(block_id, ordered_task_ids)


def move_task_to_list_block(
    task_id: int,
    target_block_id: int,
    *,
    insert_index_in_zone: int,
    target_done: bool,
) -> dict:
    _list_block_or_error(target_block_id)
    task = db.session.get(Task, int(task_id))
    if task is None:
        raise ValueError("task not found")

    source_block_id = task.block_id
    task.block_id = target_block_id
    task.status = "done" if target_done else "active"

    target_tasks = [
        t for t in tasks_for_list_block(target_block_id) if t.id != task.id
    ]
    merged_ids = merged_task_ids_after_zone_insert(
        target_tasks + [task],
        task,
        target_done=target_done,
        insert_index_in_zone=insert_index_in_zone,
    )
    target_result = apply_list_task_order(target_block_id, merged_ids)

    source_result: list[Task] = []
    if source_block_id is not None and source_block_id != target_block_id:
        source_result = apply_list_task_order(
            source_block_id,
            [t.id for t in tasks_for_list_block(source_block_id)],
        )

    return {
        "task": task,
        "target_tasks": target_result,
        "source_tasks": source_result,
        "source_block_id": source_block_id,
    }
