"""Duplicate a file and its blocks within the same topic."""

from __future__ import annotations

import copy
import re

from models import Block, File, Task, TaskView, db

_COPY_SUFFIX_RE = re.compile(r" \((copy|עותק)(?: \d+)?\)$", re.IGNORECASE)


def _clone_content(content) -> dict:
    if isinstance(content, dict):
        return copy.deepcopy(content)
    return {}


def _active_blocks(file_id: int) -> list[Block]:
    return (
        Block.query.filter_by(file_id=file_id)
        .filter(Block.archived_at.is_(None))
        .order_by(Block.order_index, Block.id)
        .all()
    )


def _copy_name(base_name: str, existing_names: set[str]) -> str:
    stripped = _COPY_SUFFIX_RE.sub("", (base_name or "").strip()).strip() or "File"
    existing = {(name or "").strip() for name in existing_names}
    candidate = f"{stripped} (copy)"
    if candidate not in existing:
        return candidate
    index = 2
    while f"{stripped} (copy {index})" in existing:
        index += 1
    return f"{stripped} (copy {index})"


def _next_topic_file_order(topic_id: int) -> int:
    last = (
        File.query.filter_by(topic_id=topic_id)
        .filter(File.archived_at.is_(None))
        .order_by(File.order_index.desc(), File.id.desc())
        .first()
    )
    if last is None or last.order_index is None:
        return 0
    return last.order_index + 1


def duplicate_file(file_id: int) -> File:
    source = db.session.get(File, int(file_id))
    if source is None:
        raise ValueError("File not found")
    if source.archived_at is not None:
        raise ValueError("Cannot duplicate an archived file")

    new_file = File(
        topic_id=source.topic_id,
        name=_copy_name(
            source.name,
            {
                (row.name or "").strip()
                for row in File.query.filter_by(topic_id=source.topic_id)
                .filter(File.archived_at.is_(None))
                .all()
            },
        ),
        type=source.type,
        order_index=_next_topic_file_order(source.topic_id),
        is_main=False,
    )
    db.session.add(new_file)
    db.session.flush()

    block_map: dict[int, Block] = {}
    task_map: dict[int, int] = {}
    order = 0

    for source_block in _active_blocks(source.id):
        if source_block.type == "task":
            old_task_id = (source_block.content or {}).get("task_id")
            old_task = (
                db.session.get(Task, int(old_task_id))
                if old_task_id is not None
                else None
            )
            new_block = Block(
                file_id=new_file.id,
                type="task",
                content={},
                order_index=order,
            )
            db.session.add(new_block)
            db.session.flush()
            block_map[source_block.id] = new_block

            if old_task is not None:
                new_task = Task(
                    block_id=new_block.id,
                    title=old_task.title,
                    status=old_task.status,
                    due_date=old_task.due_date,
                )
                db.session.add(new_task)
                db.session.flush()
                task_map[int(old_task.id)] = int(new_task.id)
                content = _clone_content(source_block.content)
                content["task_id"] = new_task.id
                new_block.content = content
            else:
                new_block.content = _clone_content(source_block.content)
            order += 1
            continue

        new_block = Block(
            file_id=new_file.id,
            type=source_block.type,
            content=_clone_content(source_block.content),
            order_index=order,
        )
        db.session.add(new_block)
        db.session.flush()
        block_map[source_block.id] = new_block
        order += 1

    for source_block in _active_blocks(source.id):
        if source_block.type != "task":
            continue
        new_block = block_map.get(source_block.id)
        if new_block is None:
            continue
        content = dict(new_block.content or {})
        list_block_id = content.get("generated_task_list_block_id")
        if list_block_id is not None:
            mapped = block_map.get(int(list_block_id))
            if mapped is not None:
                content["generated_task_list_block_id"] = mapped.id
                new_block.content = content

    for old_task_id, new_task_id in task_map.items():
        views = TaskView.query.filter_by(task_id=old_task_id).all()
        for view in views:
            db.session.add(
                TaskView(
                    task_id=new_task_id,
                    view_type=view.view_type,
                    section_name=view.section_name,
                    order_index=view.order_index,
                    section_flag=view.section_flag,
                    topic_key=view.topic_key,
                )
            )

    db.session.commit()
    return new_file
