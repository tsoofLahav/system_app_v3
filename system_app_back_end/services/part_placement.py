from __future__ import annotations

from models import Block, File, Part, Task, Topic, db
from services.part_defaults import PART_PLACEMENT_FILE_TYPES, part_default_block_specs


def next_part_order_index(topic_id: int) -> int:
    existing = (
        Part.query.filter_by(topic_id=topic_id)
        .filter(Part.archived_at.is_(None))
        .order_by(Part.order_index.desc(), Part.id.desc())
        .first()
    )
    if existing is None:
        return 0
    return (existing.order_index or 0) + 1


def part_ids_in_file(file_id: int) -> set[int]:
    blocks = (
        Block.query.filter_by(file_id=file_id)
        .filter(Block.archived_at.is_(None))
        .filter(Block.type == "header")
        .all()
    )
    result = set()
    for block in blocks:
        if block.part_id is not None:
            result.add(int(block.part_id))
            continue
        content = block.content or {}
        raw = content.get("part_id")
        if raw is not None:
            result.add(int(raw))
    return result


def _active_blocks(file_id: int) -> list[Block]:
    return (
        Block.query.filter_by(file_id=file_id)
        .filter(Block.archived_at.is_(None))
        .order_by(Block.order_index, Block.id)
        .all()
    )


def _shift_blocks_from(file_id: int, start_index: int, delta: int) -> None:
    if delta <= 0:
        return
    for block in _active_blocks(file_id):
        current = block.order_index if block.order_index is not None else 0
        if current >= start_index:
            block.order_index = current + delta


def _resolve_insert_index(
    blocks: list[Block],
    insert_after_block_id: int | None,
    insert_index: int | None = None,
) -> int:
    if insert_index is not None:
        return max(0, int(insert_index))
    if insert_after_block_id is not None:
        for block in blocks:
            if block.id == insert_after_block_id:
                return (block.order_index if block.order_index is not None else 0) + 1
    if not blocks:
        return 0
    return max((b.order_index if b.order_index is not None else 0) for b in blocks) + 1


def _header_content(part: Part) -> dict:
    return {
        "text": part.name,
        "level": 2,
        "part_id": part.id,
    }


def place_part_in_file(
    file: File,
    *,
    part: Part,
    insert_after_block_id: int | None = None,
    insert_index: int | None = None,
) -> dict:
    if file.type not in PART_PLACEMENT_FILE_TYPES:
        raise ValueError(f"part placement is not supported for file type {file.type}")

    existing = part_ids_in_file(file.id)
    if part.id in existing:
        raise ValueError("part is already placed in this file")

    blocks = _active_blocks(file.id)
    insert_at = _resolve_insert_index(
        blocks,
        insert_after_block_id,
        insert_index=insert_index,
    )
    default_specs = list(part_default_block_specs(file.type))
    task_slot = 1 if file.type == "tasks" else 0
    insert_count = 1 + len(default_specs) + task_slot
    _shift_blocks_from(file.id, insert_at, insert_count)

    created_blocks: list[Block] = []
    order = insert_at

    header = Block(
        file_id=file.id,
        type="header",
        content=_header_content(part),
        order_index=order,
        part_id=part.id,
    )
    db.session.add(header)
    db.session.flush()
    created_blocks.append(header)
    order += 1

    for block_type, content in default_specs:
        block = Block(
            file_id=file.id,
            type=block_type,
            content=dict(content),
            order_index=order,
            part_id=part.id,
        )
        db.session.add(block)
        db.session.flush()
        created_blocks.append(block)
        order += 1

    created_task = None
    if file.type == "tasks":
        task_block = Block(
            file_id=file.id,
            type="task",
            content={},
            order_index=order,
            part_id=part.id,
        )
        db.session.add(task_block)
        db.session.flush()
        task = Task(block_id=task_block.id, title="", status="active")
        db.session.add(task)
        db.session.flush()
        task_block.content = {"task_id": task.id}
        created_blocks.append(task_block)
        created_task = task
        order += 1

    return {
        "part": part.to_dict(),
        "blocks": [block.to_dict() for block in created_blocks],
        "task": created_task.to_dict() if created_task is not None else None,
    }


def create_part_for_topic(
    topic: Topic,
    *,
    name: str,
    file: File | None = None,
    insert_after_block_id: int | None = None,
    insert_index: int | None = None,
) -> dict:
    trimmed = str(name or "").strip()
    if not trimmed:
        raise ValueError("name is required")

    part = Part(
        topic_id=topic.id,
        name=trimmed,
        order_index=next_part_order_index(topic.id),
    )
    db.session.add(part)
    db.session.flush()

    if file is None:
        return {"part": part.to_dict()}

    placement = place_part_in_file(
        file,
        part=part,
        insert_after_block_id=insert_after_block_id,
        insert_index=insert_index,
    )
    return {
        "part": placement["part"],
        "blocks": placement["blocks"],
        "task": placement.get("task"),
    }
