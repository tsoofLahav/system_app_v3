"""Sync execution and tasks part headers to match the plan file structure."""

from __future__ import annotations

import re
from datetime import datetime

from models import Block, Task, db

_PART_KEY_RE = re.compile(r"[^a-z0-9\u0590-\u05FF]+")


def _part_key(title: str) -> str:
    return _PART_KEY_RE.sub("", (title or "").strip().lower())


def _header_text(block: Block) -> str:
    if block.type != "header":
        return ""
    return str((block.content or {}).get("text") or "").strip()


def _active_blocks(file_id: int) -> list[Block]:
    return (
        Block.query.filter_by(file_id=file_id)
        .filter(Block.archived_at.is_(None))
        .order_by(Block.order_index, Block.id)
        .all()
    )


def _sections_for_file(file_id: int) -> dict:
    blocks = _active_blocks(file_id)
    preamble = []
    sections = []
    current = None
    for block in blocks:
        if block.type == "header" and _header_text(block):
            current = {
                "title": _header_text(block),
                "blocks": [block],
            }
            sections.append(current)
            continue
        if current is None:
            preamble.append(block)
        else:
            current["blocks"].append(block)
    return {"preamble": preamble, "sections": sections}


def _plan_part_titles(plan_file_id: int) -> list[str]:
    return [
        section["title"]
        for section in _sections_for_file(plan_file_id)["sections"]
        if section.get("title")
    ]


def _clone_block_content(block: Block) -> dict:
    content = block.content or {}
    if isinstance(content, dict):
        return dict(content)
    return {}


def _archive_all_blocks(file_id: int) -> None:
    for block in _active_blocks(file_id):
        block.archived_at = datetime.utcnow()


def _sync_execution_to_plan(execution_file, part_titles: list[str]) -> None:
    layout = _sections_for_file(execution_file.id)
    content_by_key: dict[str, list[Block]] = {}
    for section in layout["sections"]:
        key = _part_key(section["title"])
        if not key:
            continue
        content_by_key[key] = [
            block
            for block in section["blocks"]
            if block.type != "header" and block.type != "task"
        ]

    _archive_all_blocks(execution_file.id)

    order = 0
    for title in part_titles:
        db.session.add(
            Block(
                file_id=execution_file.id,
                type="header",
                content={"text": title, "level": 2},
                order_index=order,
            )
        )
        order += 1
        for source in content_by_key.get(_part_key(title)) or []:
            db.session.add(
                Block(
                    file_id=execution_file.id,
                    type=source.type,
                    content=_clone_block_content(source),
                    order_index=order,
                )
            )
            order += 1


def _sync_tasks_to_plan(tasks_file, part_titles: list[str]) -> None:
    layout = _sections_for_file(tasks_file.id)
    task_blocks_by_key: dict[str, list[Block]] = {}
    old_task_ids: list[int] = []
    for section in layout["sections"]:
        key = _part_key(section["title"])
        if not key:
            continue
        task_blocks = [block for block in section["blocks"] if block.type == "task"]
        task_blocks_by_key[key] = task_blocks
        for block in task_blocks:
            task_id = (block.content or {}).get("task_id")
            if task_id is not None:
                old_task_ids.append(int(task_id))

    tasks_by_id = {}
    if old_task_ids:
        for task in Task.query.filter(Task.id.in_(old_task_ids)).all():
            tasks_by_id[task.id] = task

    _archive_all_blocks(tasks_file.id)

    order = 0
    task_list_block = Block(
        file_id=tasks_file.id,
        type="task_list",
        content={},
        order_index=order,
    )
    db.session.add(task_list_block)
    db.session.flush()
    order += 1

    for title in part_titles:
        db.session.add(
            Block(
                file_id=tasks_file.id,
                type="header",
                content={"text": title, "level": 2},
                order_index=order,
            )
        )
        order += 1
        for source in task_blocks_by_key.get(_part_key(title)) or []:
            old_task_id = (source.content or {}).get("task_id")
            old_task = (
                tasks_by_id.get(int(old_task_id)) if old_task_id is not None else None
            )
            title_text = (old_task.title if old_task else "").strip()
            if not title_text:
                continue
            new_task = Task(
                block_id=task_list_block.id,
                title=title_text,
                status=old_task.status if old_task else "active",
                due_date=old_task.due_date if old_task else None,
            )
            db.session.add(new_task)
            db.session.flush()
            db.session.add(
                Block(
                    file_id=tasks_file.id,
                    type="task",
                    content={"task_id": new_task.id},
                    order_index=order,
                )
            )
            order += 1

    db.session.flush()


def sync_execution_and_tasks_to_plan(plan_file, execution_file, tasks_file) -> None:
    part_titles = _plan_part_titles(plan_file.id)
    if not part_titles:
        return

    _sync_execution_to_plan(execution_file, part_titles)
    _sync_tasks_to_plan(tasks_file, part_titles)
