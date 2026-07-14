"""Parse part sections from a log file."""

from __future__ import annotations

from services.part_resolver import part_by_id, part_id_for_block, parts_for_topic
from services.unit_mapper import _block_to_units, _table_rows_to_lines


def _active_blocks(file_id: int):
    from models import Block

    return (
        Block.query.filter_by(file_id=file_id)
        .filter(Block.archived_at.is_(None))
        .order_by(Block.order_index, Block.id)
        .all()
    )


def _flatten_blocks_to_text(blocks) -> str:
    lines = []
    for block in blocks:
        if block.type == "table":
            lines.extend(_table_rows_to_lines(block.content or {}))
            continue
        for unit in _block_to_units(block, {}):
            text = (unit.get("text") or "").strip()
            if text and block.type != "header":
                lines.append(text)
    return "\n".join(lines).strip()


def log_file_date(log_file) -> str:
    from datetime import datetime

    if log_file.created_at:
        return log_file.created_at.strftime("%Y-%m-%d")
    return datetime.utcnow().strftime("%Y-%m-%d")


def parse_log_parts(log_file, topic_id: int) -> list[dict]:
    blocks = _active_blocks(log_file.id)
    sections = []
    current = None

    for block in blocks:
        if block.type == "header":
            part_id = part_id_for_block(block)
            if current is not None:
                sections.append(current)
            name = (block.content or {}).get("text") or ""
            if part_id is not None:
                part = part_by_id(part_id)
                if part is not None:
                    name = part.name
            current = {
                "part_id": part_id,
                "part_name": str(name).strip() or "Part",
                "header_block_id": block.id,
                "content_blocks": [],
            }
            continue
        if current is not None:
            current["content_blocks"].append(block)

    if current is not None:
        sections.append(current)

    if not sections:
        preamble = [b for b in blocks if b.type != "header"]
        if preamble:
            sections.append(
                {
                    "part_id": None,
                    "part_name": "Log",
                    "header_block_id": None,
                    "content_blocks": preamble,
                }
            )

    project_parts = {part.id: part for part in parts_for_topic(topic_id)}
    result = []
    for section in sections:
        part_id = section.get("part_id")
        text = _flatten_blocks_to_text(section["content_blocks"])
        if not text.strip():
            continue
        is_new = part_id is None or part_id not in project_parts
        part_name = section["part_name"]
        if part_id in project_parts:
            part_name = project_parts[part_id].name
        result.append(
            {
                "part_id": part_id,
                "part_name": part_name,
                "is_new": is_new,
                "log_text": text,
            }
        )
    return result
