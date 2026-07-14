from __future__ import annotations

from models import Block, File, Part, db

CORE_PART_FILE_TYPES = ("plan", "execution", "tasks")


def parts_for_topic(topic_id: int, *, include_archived: bool = False) -> list[Part]:
    query = Part.query.filter_by(topic_id=topic_id)
    if not include_archived:
        query = query.filter(Part.archived_at.is_(None))
    return query.order_by(Part.order_index, Part.id).all()


def part_by_id(part_id: int) -> Part | None:
    return db.session.get(Part, int(part_id))


def part_id_for_block(block: Block) -> int | None:
    if block.part_id is not None:
        return int(block.part_id)
    content = block.content or {}
    raw = content.get("part_id")
    if raw is None:
        return None
    try:
        return int(raw)
    except (TypeError, ValueError):
        return None


def _active_blocks(file_id: int) -> list[Block]:
    return (
        Block.query.filter_by(file_id=file_id)
        .filter(Block.archived_at.is_(None))
        .order_by(Block.order_index, Block.id)
        .all()
    )


def blocks_for_part_in_file(file_id: int, part_id: int) -> list[Block]:
    part_id = int(part_id)
    blocks = _active_blocks(file_id)
    result = []
    in_part = False
    for block in blocks:
        block_part_id = part_id_for_block(block)
        if block.type == "header" and block_part_id == part_id:
            in_part = True
            result.append(block)
            continue
        if block.type == "header" and block_part_id is not None:
            in_part = False
            continue
        if in_part or block_part_id == part_id:
            result.append(block)
    return result


def files_containing_part(topic_id: int, part_id: int) -> list[str]:
    part_id = int(part_id)
    files = (
        File.query.filter_by(topic_id=topic_id)
        .filter(File.archived_at.is_(None))
        .filter(File.type.in_(CORE_PART_FILE_TYPES))
        .order_by(File.order_index, File.id)
        .all()
    )
    result = []
    for file in files:
        if part_id in _part_ids_for_file(file.id):
            result.append(file.type)
    return result


def _part_ids_for_file(file_id: int) -> set[int]:
    ids = set()
    for block in _active_blocks(file_id):
        if block.type != "header":
            continue
        part_id = part_id_for_block(block)
        if part_id is not None:
            ids.add(part_id)
    return ids


def resolve_part_name_to_id(topic_id: int, name: str) -> int | None:
    key = _part_key(name)
    if not key:
        return None
    for part in parts_for_topic(topic_id):
        if _part_key(part.name) == key:
            return part.id
    return None


def resolve_part_id_to_name(topic_id: int, part_id: int | None) -> str | None:
    if part_id is None:
        return None
    part = part_by_id(part_id)
    if part is None or part.topic_id != topic_id:
        return None
    return part.name


def task_part_id_map(tasks_file: File) -> dict[int, int]:
    result = {}
    current_part_id = None
    for block in _active_blocks(tasks_file.id):
        if block.type == "header":
            current_part_id = part_id_for_block(block)
            continue
        if block.type != "task":
            continue
        part_id = part_id_for_block(block) or current_part_id
        if part_id is None:
            continue
        task_id = (block.content or {}).get("task_id")
        if task_id is not None:
            result[int(task_id)] = int(part_id)
    return result


def _part_key(value) -> str:
    return " ".join(str(value or "").strip().casefold().split())
