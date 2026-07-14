"""Deep-copy a file, its blocks, and task rows."""

from __future__ import annotations

from copy import deepcopy

from models import Block, File, Task, db


def _shift_file_orders(topic_id: int, is_main: bool | None, from_index: int) -> None:
    query = (
        File.query.filter_by(topic_id=topic_id)
        .filter(File.archived_at.is_(None))
    )
    if is_main is not None:
        query = query.filter_by(is_main=is_main)
    files = query.order_by(File.order_index, File.id).all()
    for file in files:
        current = file.order_index if file.order_index is not None else 0
        if current >= from_index:
            file.order_index = current + 1


def _active_blocks(file_id: int) -> list[Block]:
    return (
        Block.query.filter_by(file_id=file_id)
        .filter(Block.archived_at.is_(None))
        .order_by(Block.order_index, Block.id)
        .all()
    )


def duplicate_file(file: File, *, name: str | None = None) -> File:
    if file.archived_at is not None:
        raise ValueError("Cannot duplicate an archived file")

    source_blocks = _active_blocks(file.id)
    order_index = (file.order_index if file.order_index is not None else 0) + 1
    _shift_file_orders(file.topic_id, file.is_main, order_index)

    duplicate = File(
        topic_id=file.topic_id,
        name=(name or f"{file.name} copy").strip(),
        type=file.type,
        order_index=order_index,
        is_main=file.is_main,
    )
    db.session.add(duplicate)
    db.session.flush()

    block_map: dict[int, Block] = {}
    pending_task_blocks: list[tuple[Block, int]] = []

    for source in source_blocks:
        content = deepcopy(source.content or {})
        new_block = Block(
            file_id=duplicate.id,
            type=source.type,
            content=content,
            order_index=source.order_index,
            part_id=source.part_id,
        )
        db.session.add(new_block)
        db.session.flush()
        block_map[source.id] = new_block

        if source.type == "task":
            old_task_id = content.get("task_id")
            if old_task_id is not None:
                pending_task_blocks.append((new_block, int(old_task_id)))
                new_block.content = {}
                db.session.flush()

    for new_block, old_task_id in pending_task_blocks:
        old_task = db.session.get(Task, old_task_id)
        if old_task is None:
            continue
        old_anchor_id = old_task.block_id
        new_anchor = block_map.get(old_anchor_id) if old_anchor_id is not None else None
        new_task = Task(
            block_id=new_anchor.id if new_anchor is not None else new_block.id,
            title=old_task.title,
            status=old_task.status,
            due_date=old_task.due_date,
        )
        db.session.add(new_task)
        db.session.flush()
        new_block.content = {"task_id": new_task.id}

    return duplicate
