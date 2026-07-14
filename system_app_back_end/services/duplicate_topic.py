"""Deep-copy a topic with parts, files, blocks, and tasks."""

from __future__ import annotations

from copy import deepcopy

from models import Block, File, Part, Task, Topic, db
from services.part_resolver import parts_for_topic


def _active_blocks(file_id: int) -> list[Block]:
    return (
        Block.query.filter_by(file_id=file_id)
        .filter(Block.archived_at.is_(None))
        .order_by(Block.order_index, Block.id)
        .all()
    )


def _remap_block_content(content: dict, part_map: dict[int, int]) -> dict:
    content = deepcopy(content or {})
    raw = content.get("part_id")
    if raw is not None:
        try:
            old_id = int(raw)
        except (TypeError, ValueError):
            return content
        if old_id in part_map:
            content["part_id"] = part_map[old_id]
    return content


def _duplicate_file_into_topic(
    source_file: File,
    *,
    topic_id: int,
    part_map: dict[int, int],
    source_topic_id: int,
    new_topic_id: int,
) -> File:
    anchor_topic_id = source_file.anchor_topic_id
    if anchor_topic_id == source_topic_id:
        anchor_topic_id = new_topic_id

    duplicate = File(
        topic_id=topic_id,
        name=source_file.name,
        type=source_file.type,
        order_index=source_file.order_index,
        is_main=source_file.is_main,
        anchor_topic_id=anchor_topic_id,
    )
    db.session.add(duplicate)
    db.session.flush()

    source_blocks = _active_blocks(source_file.id)
    block_map: dict[int, Block] = {}
    pending_task_blocks: list[tuple[Block, int]] = []

    for source in source_blocks:
        content = _remap_block_content(source.content or {}, part_map)
        new_part_id = None
        if source.part_id is not None:
            new_part_id = part_map.get(int(source.part_id))

        new_block = Block(
            file_id=duplicate.id,
            type=source.type,
            content=content,
            order_index=source.order_index,
            part_id=new_part_id,
        )
        db.session.add(new_block)
        db.session.flush()
        block_map[source.id] = new_block

        if source.type == "task":
            old_task_id = (source.content or {}).get("task_id")
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


def duplicate_topic(topic: Topic, *, name: str | None = None) -> Topic:
    if topic.archived_at is not None:
        raise ValueError("Cannot duplicate an archived topic")

    duplicate = Topic(
        name=(name or f"{topic.name} copy").strip(),
        type=topic.type,
        icon=topic.icon,
        color=topic.color,
        parent_id=topic.parent_id,
    )
    db.session.add(duplicate)
    db.session.flush()

    part_map: dict[int, int] = {}
    for part in parts_for_topic(topic.id):
        new_part = Part(
            topic_id=duplicate.id,
            name=part.name,
            order_index=part.order_index or 0,
        )
        db.session.add(new_part)
        db.session.flush()
        part_map[part.id] = new_part.id

    source_files = (
        File.query.filter_by(topic_id=topic.id)
        .filter(File.archived_at.is_(None))
        .order_by(File.order_index, File.id)
        .all()
    )
    for source_file in source_files:
        _duplicate_file_into_topic(
            source_file,
            topic_id=duplicate.id,
            part_map=part_map,
            source_topic_id=topic.id,
            new_topic_id=duplicate.id,
        )

    return duplicate
