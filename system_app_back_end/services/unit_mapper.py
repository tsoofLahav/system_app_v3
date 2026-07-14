import re

from models import Block, Task, db

_SENTENCE_SPLIT = re.compile(r"(?<=[.!?])\s+|\n+")
_LIST_ITEM_PREFIX = re.compile(r"^\s*(?:[•\-\*]|\d+[\.\)])\s*")


def content_units_from_merged(units: list[dict]) -> list[dict]:
    result = []
    for unit in units or []:
        unit = dict(unit)
        kind = unit.get("kind")
        text = _sanitize_unit_text(unit.get("text") or "", kind)
        if not text:
            continue
        unit["text"] = text
        result.append(unit)
    return result


def _sanitize_unit_text(text: str, kind) -> str:
    text = str(text or "").replace("\r\n", "\n").strip()
    if kind == "list_item":
        text = text.lstrip("\n")
        text = _LIST_ITEM_PREFIX.sub("", text).strip()
    return text


def units_from_file(file_id):
    blocks = (
        Block.query.filter_by(file_id=file_id)
        .filter(Block.archived_at.is_(None))
        .order_by(Block.order_index, Block.id)
        .all()
    )
    task_ids = []
    for block in blocks:
        if block.type == "task":
            task_id = (block.content or {}).get("task_id")
            if task_id:
                task_ids.append(int(task_id))
    tasks_by_id = {}
    if task_ids:
        for task in Task.query.filter(Task.id.in_(task_ids)).all():
            tasks_by_id[task.id] = task.title

    units = []
    for block in blocks:
        if block.type == "task_list":
            continue
        units.extend(_block_to_units(block, tasks_by_id))
    return units


def flatten_units_for_ai(units, title):
    lines = []
    for unit in units:
        text = (unit.get("text") or "").strip()
        if text:
            lines.append(f"[{unit['id']}] {text}")
    body = "\n".join(lines)
    return f"=== {title.upper()} ===\n{body}".strip()


def flatten_doc_file_for_ai(doc_file):
    blocks = (
        Block.query.filter_by(file_id=doc_file.id)
        .filter(Block.archived_at.is_(None))
        .order_by(Block.order_index, Block.id)
        .all()
    )
    lines = []
    for block in blocks:
        if block.type == "table":
            lines.extend(_table_rows_to_lines(block.content or {}))
            continue
        for unit in _block_to_units(block, {}):
            text = (unit.get("text") or "").strip()
            if text:
                lines.append(text)
    body = "\n".join(lines)
    return f"=== {doc_file.name.upper()} ===\n{body}".strip()


def flatten_process_files_for_ai(plan_file, doc_file, tasks_file):
    return {
        "plan": flatten_units_for_ai(units_from_file(plan_file.id), plan_file.name),
        "documentation": flatten_doc_file_for_ai(doc_file),
        "tasks": flatten_units_for_ai(units_from_file(tasks_file.id), tasks_file.name),
    }


def detect_language(*texts):
    combined = _language_signal_text("\n".join(texts))
    hebrew = len(re.findall(r"[\u0590-\u05FF]", combined))
    latin = len(re.findall(r"[A-Za-z]", combined))
    return "he" if hebrew > latin else "en"


def _language_signal_text(text):
    lines = []
    for line in (text or "").splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith("===") and stripped.endswith("==="):
            continue
        stripped = re.sub(r"^\[[^\]]+\]\s*", "", stripped)
        lines.append(stripped)
    return "\n".join(lines)


def apply_units_to_file(file, units):
    from models import Block, Task

    order = 0
    list_items = []
    task_list_block = None
    has_tasks = any(unit.get("kind") == "task" for unit in units)

    if has_tasks:
        task_list_block = Block(
            file_id=file.id,
            type="task_list",
            content={},
            order_index=order,
        )
        db.session.add(task_list_block)
        db.session.flush()
        order += 1

    prose_buffer = []
    prose_kind = None
    prose_block_id = None

    def flush_list():
        nonlocal order, list_items
        if not list_items:
            return
        db.session.add(
            Block(
                file_id=file.id,
                type="list",
                content={"items": list_items},
                order_index=order,
            )
        )
        order += 1
        list_items = []

    def flush_prose():
        nonlocal order, prose_buffer, prose_kind, prose_block_id
        if not prose_buffer:
            prose_kind = None
            prose_block_id = None
            return
        text = " ".join(prose_buffer).strip()
        if text:
            if prose_kind == "header":
                db.session.add(
                    Block(
                        file_id=file.id,
                        type="header",
                        content={"text": text, "level": 2},
                        order_index=order,
                    )
                )
            elif prose_kind == "summary":
                db.session.add(
                    Block(
                        file_id=file.id,
                        type="summary",
                        content={"text": text},
                        order_index=order,
                    )
                )
            else:
                db.session.add(
                    Block(
                        file_id=file.id,
                        type="text",
                        content={"text": text},
                        order_index=order,
                    )
                )
            order += 1
        prose_buffer = []
        prose_kind = None
        prose_block_id = None

    for unit in units:
        kind = unit.get("kind")
        text = (unit.get("text") or "").strip()
        block_id = unit.get("block_id")

        if kind in ("paragraph", "header", "summary"):
            if (
                text
                and prose_kind == kind
                and prose_block_id is not None
                and block_id is not None
                and prose_block_id == block_id
            ):
                prose_buffer.append(text)
                continue
            flush_list()
            flush_prose()
            if text:
                prose_kind = kind
                prose_block_id = block_id
                prose_buffer = [text]
            continue

        flush_prose()
        if kind == "list_item":
            if text:
                list_items.append({"text": text})
            continue
        flush_list()
        if kind == "task":
            if not text or task_list_block is None:
                continue
            task = Task(
                block_id=task_list_block.id,
                title=text,
                status="active",
            )
            db.session.add(task)
            db.session.flush()
            db.session.add(
                Block(
                    file_id=file.id,
                    type="task",
                    content={"task_id": task.id},
                    order_index=order,
                )
            )
            order += 1
            continue

    flush_list()
    flush_prose()
    db.session.flush()


def _split_prose_units(block_id, kind, text):
    text = (text or "").strip()
    if not text:
        return []
    parts = [part.strip() for part in _SENTENCE_SPLIT.split(text) if part.strip()]
    if not parts:
        return []
    return [
        {
            "id": f"block:{block_id}:sent:{index}",
            "kind": kind,
            "text": part,
            "block_id": block_id,
        }
        for index, part in enumerate(parts)
    ]


def _table_rows_to_lines(content):
    lines = []
    for row in content.get("rows") or []:
        cells = [str(cell).strip() for cell in row if str(cell).strip()]
        if cells:
            lines.append(" | ".join(cells))
    return lines


def _block_to_units(block, tasks_by_id):
    content = dict(block.content or {})
    if block.type == "text":
        return _split_prose_units(block.id, "paragraph", content.get("text") or "")
    if block.type == "header":
        return _split_prose_units(block.id, "header", content.get("text") or "")
    if block.type == "summary":
        return _split_prose_units(block.id, "summary", content.get("text") or "")
    if block.type == "list":
        units = []
        for index, item in enumerate(content.get("items") or []):
            text = (item.get("text") or "").strip()
            if not text:
                continue
            units.append(
                {
                    "id": f"block:{block.id}:item:{index}",
                    "kind": "list_item",
                    "text": text,
                    "block_id": block.id,
                    "path": ["items", index],
                }
            )
        return units
    if block.type == "task":
        task_id = content.get("task_id")
        title = tasks_by_id.get(int(task_id), "") if task_id else ""
        if not title:
            return []
        return [
            {
                "id": f"task:{task_id}",
                "kind": "task",
                "text": title,
                "block_id": block.id,
                "task_id": int(task_id),
            }
        ]
    return []


def _tasks_by_id_for_part_blocks(blocks, tasks_by_id_from_blocks: dict[int, str] | None = None):
    """Tasks linked to this part's task_list blocks — matches the file editor."""
    list_ids = [int(block.id) for block in blocks if block.type == "task_list"]
    if list_ids:
        tasks = (
            Task.query.filter(Task.block_id.in_(list_ids))
            .filter(Task.archived_at.is_(None))
            .all()
        )
        return {task.id: task.title for task in tasks}
    return tasks_by_id_from_blocks or {}


def units_for_part_in_file(file_id: int, part_id: int) -> list[dict]:
    from services.ai_smart_update.document_segments import (
        segments_from_part_blocks,
        segments_to_units,
    )
    from services.part_resolver import blocks_for_part_in_file

    blocks = blocks_for_part_in_file(file_id, part_id)
    task_ids = []
    for block in blocks:
        if block.type == "task":
            task_id = (block.content or {}).get("task_id")
            if task_id:
                task_ids.append(int(task_id))
    fallback_tasks_by_id = {}
    if task_ids:
        for task in Task.query.filter(Task.id.in_(task_ids)).all():
            fallback_tasks_by_id[task.id] = task.title
    tasks_by_id = _tasks_by_id_for_part_blocks(blocks, fallback_tasks_by_id)

    segments = segments_from_part_blocks(blocks, tasks_by_id=tasks_by_id)
    units = segments_to_units(segments)
    result = []
    for unit in units:
        unit = dict(unit)
        unit["id"] = f"part:{part_id}:{unit['id']}"
        result.append(unit)
    return result


def flatten_part_files_for_ai(
    *,
    part_name: str,
    log_text: str,
    plan_units,
    execution_units,
    tasks_units,
) -> str:
    sections = [
        f"=== LOG ({part_name}) ===\n{log_text.strip()}",
        flatten_units_for_ai(plan_units, f"Plan — {part_name}"),
        flatten_units_for_ai(execution_units, f"Execution — {part_name}"),
        flatten_units_for_ai(tasks_units, f"Tasks — {part_name}"),
    ]
    return "\n\n".join(section for section in sections if section.strip())


def apply_units_to_part_in_file(file, part_id: int, units: list[dict]):
    from services.part_resolver import blocks_for_part_in_file

    part_blocks = blocks_for_part_in_file(file.id, part_id)
    content_blocks = [b for b in part_blocks if b.type != "header"]
    for block in content_blocks:
        db.session.delete(block)
    db.session.flush()

    denormalized = []
    prefix = f"part:{part_id}:"
    for unit in content_units_from_merged(units):
        unit = dict(unit)
        unit_id = unit.get("id") or ""
        if unit_id.startswith(prefix):
            unit["id"] = unit_id[len(prefix) :]
        denormalized.append(unit)

    start_order = 0
    if part_blocks:
        header = part_blocks[0]
        start_order = (header.order_index or 0) + 1

    _apply_units_at_order(file, denormalized, start_order, part_id)


def _apply_units_at_order(file, units, start_order: int, part_id: int | None):
    order = start_order
    list_items = []
    task_list_block = None
    has_tasks = any(unit.get("kind") == "task" for unit in units)

    if has_tasks:
        task_list_block = Block(
            file_id=file.id,
            type="task_list",
            content={},
            order_index=order,
            part_id=part_id,
        )
        db.session.add(task_list_block)
        db.session.flush()
        order += 1

    prose_buffer = []
    prose_kind = None
    prose_segment_id = None

    def flush_list():
        nonlocal order, list_items
        non_empty = [
            item
            for item in list_items
            if (item.get("text") or "").strip()
        ]
        if not non_empty:
            list_items.clear()
            return
        db.session.add(
            Block(
                file_id=file.id,
                type="list",
                content={"items": non_empty, "list_style": "bullet"},
                order_index=order,
                part_id=part_id,
            )
        )
        order += 1
        list_items.clear()

    def flush_prose():
        nonlocal order, prose_buffer, prose_kind, prose_segment_id
        if not prose_buffer:
            prose_kind = None
            prose_segment_id = None
            return
        text = " ".join(prose_buffer).strip()
        if text:
            db.session.add(
                Block(
                    file_id=file.id,
                    type=prose_kind or "text",
                    content={"text": text},
                    order_index=order,
                    part_id=part_id,
                )
            )
            order += 1
        prose_buffer = []
        prose_kind = None
        prose_segment_id = None

    for unit in units:
        kind = unit.get("kind")
        text = _sanitize_unit_text(unit.get("text") or "", kind)
        segment_key = unit.get("segment_id") or unit.get("block_id")

        if kind in ("paragraph", "text", "summary"):
            flush_list()
            if text:
                if (
                    prose_buffer
                    and prose_segment_id is not None
                    and segment_key is not None
                    and str(prose_segment_id) != str(segment_key)
                ):
                    flush_prose()
                if not prose_kind:
                    prose_kind = "text"
                if prose_segment_id is None and segment_key is not None:
                    prose_segment_id = segment_key
                prose_buffer.append(text)
            continue

        flush_prose()
        if kind == "list_item":
            if text:
                list_items.append({"text": text})
            continue
        flush_list()
        if kind == "task" and text and task_list_block is not None:
            task = Task(
                block_id=task_list_block.id,
                title=text,
                status="active",
            )
            db.session.add(task)
            db.session.flush()
            db.session.add(
                Block(
                    file_id=file.id,
                    type="task",
                    content={"task_id": task.id},
                    order_index=order,
                    part_id=part_id,
                )
            )
            order += 1

    flush_list()
    flush_prose()
    db.session.flush()
