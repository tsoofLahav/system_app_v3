"""Write helpers for interactive AI tools."""

from __future__ import annotations

from models import Block, File, Task, db
from services.doc_table_rows import DEFAULT_TABLE_HEADER, insert_row_into_table_block


def _next_order(file_id: int) -> int:
    last = (
        Block.query.filter_by(file_id=file_id)
        .order_by(Block.order_index.desc(), Block.id.desc())
        .first()
    )
    if last is None or last.order_index is None:
        return 0
    return last.order_index + 1


def _active_blocks(file_id: int) -> list[Block]:
    return (
        Block.query.filter_by(file_id=file_id)
        .filter(Block.archived_at.is_(None))
        .order_by(Block.order_index, Block.id)
        .all()
    )


def _ensure_task_list_block(file_id: int) -> Block:
    existing = (
        Block.query.filter_by(file_id=file_id, type="task_list")
        .order_by(Block.id)
        .first()
    )
    if existing:
        return existing
    block = Block(
        file_id=file_id,
        type="task_list",
        content={},
        order_index=_next_order(file_id),
    )
    db.session.add(block)
    db.session.flush()
    return block


def add_task_to_file(file_id: int, title: str) -> Task:
    list_block = _ensure_task_list_block(file_id)
    task = Task(block_id=list_block.id, title=title, status="active")
    db.session.add(task)
    db.session.flush()
    task_block = Block(
        file_id=file_id,
        type="task",
        content={"task_id": task.id},
        order_index=_next_order(file_id),
    )
    db.session.add(task_block)
    db.session.flush()
    return task


def _ensure_table_block(file: File) -> Block:
    blocks = _active_blocks(file.id)
    for block in blocks:
        if block.type == "table":
            return block

    insert_index = len(blocks)
    for index, block in enumerate(blocks):
        if block.type in ("graph", "text"):
            insert_index = index
            break

    for block in blocks:
        if block.order_index is not None and block.order_index >= insert_index:
            block.order_index = (block.order_index or 0) + 1

    table_block = Block(
        file_id=file.id,
        type="table",
        content={"rows": [DEFAULT_TABLE_HEADER[:], ["", ""]]},
        order_index=insert_index,
    )
    db.session.add(table_block)
    db.session.flush()
    return table_block


def insert_dated_doc_row(*, file_id: int, text: str, entry_date: str) -> Block:
    file = db.session.get(File, int(file_id))
    if file is None:
        raise ValueError("File not found")

    table_block = _ensure_table_block(file)
    insert_row_into_table_block(table_block, entry_date, text)
    db.session.flush()
    return table_block
