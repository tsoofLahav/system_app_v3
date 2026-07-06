"""Sync execution and tasks part headers to match the plan file structure."""

from __future__ import annotations

import re
from datetime import datetime

from models import Block, db

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


def sync_execution_and_tasks_to_plan(plan_file, execution_file, tasks_file) -> None:
    part_titles = _plan_part_titles(plan_file.id)
    if not part_titles:
        return

    for target_file in (execution_file, tasks_file):
        layout = _sections_for_file(target_file.id)
        content_by_key: dict[str, list[Block]] = {}
        for section in layout["sections"]:
            key = _part_key(section["title"])
            if not key:
                continue
            content_by_key[key] = [
                block for block in section["blocks"] if block.type != "header"
            ]

        for block in _active_blocks(target_file.id):
            block.archived_at = datetime.utcnow()

        order = 0
        for title in part_titles:
            db.session.add(
                Block(
                    file_id=target_file.id,
                    type="header",
                    content={"text": title, "level": 2},
                    order_index=order,
                )
            )
            order += 1
            section_blocks = content_by_key.get(_part_key(title)) or []
            for source in section_blocks:
                db.session.add(
                    Block(
                        file_id=target_file.id,
                        type=source.type,
                        content=_clone_block_content(source),
                        order_index=order,
                    )
                )
                order += 1

        preamble = layout["preamble"]
        if preamble and not part_titles:
            for source in preamble:
                db.session.add(
                    Block(
                        file_id=target_file.id,
                        type=source.type,
                        content=_clone_block_content(source),
                        order_index=order,
                    )
                )
                order += 1

    db.session.flush()
