import re

from models import Block, Task, db

_SENTENCE_SPLIT = re.compile(r"(?<=[.!?])\s+|\n+")


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


def extract_part_names(units):
    return [
        (unit.get("text") or "").strip()
        for unit in units
        if unit.get("kind") == "header" and (unit.get("text") or "").strip()
    ]


def annotate_units_with_parts(units):
    annotated = []
    current_part = None
    for unit in units:
        row = dict(unit)
        if row.get("kind") == "header":
            current_part = (row.get("text") or "").strip() or None
        row["part"] = current_part
        annotated.append(row)
    return annotated


def flatten_file_by_parts_for_ai(units, title):
    part_names = extract_part_names(units)
    lines = [f"=== {title.upper()} ==="]
    if part_names:
        lines.append(
            "PART LIST: " + " | ".join(f'"{name}"' for name in part_names)
        )
    else:
        lines.append("PART LIST: (none — no part headers in this file yet)")
    lines.append("")

    current_part = None
    for unit in units:
        kind = unit.get("kind")
        text = (unit.get("text") or "").strip()
        if kind == "header":
            current_part = text
            lines.append(f"--- PART: {text or '(untitled)'} ---")
            if text:
                lines.append(f"[{unit['id']}] {text}")
            continue
        if current_part is None:
            if not lines or lines[-1] != "--- BEFORE PARTS ---":
                lines.append("--- BEFORE PARTS ---")
        if text:
            lines.append(f"[{unit['id']}] {text}")

    return "\n".join(lines).strip()


def summarize_parts_for_mapping(units, max_essence_lines=4):
    """Compact per-part essence for Step 0 overlap detection."""
    lines = []
    current_part = None
    essence_count = 0

    for unit in units:
        kind = unit.get("kind")
        text = (unit.get("text") or "").strip()
        if kind == "header":
            if current_part is not None:
                lines.append("")
            current_part = text or "(untitled)"
            essence_count = 0
            lines.append(f"PART: {current_part}")
            continue
        if not text or essence_count >= max_essence_lines:
            continue
        lines.append(f"  - {text}")
        essence_count += 1

    return "\n".join(lines).strip() or "(no parts)"


def flatten_units_for_ai(units, title):
    return flatten_file_by_parts_for_ai(units, title)


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


def flatten_input_file_for_ai(input_file):
    return flatten_units_for_ai(units_from_file(input_file.id), input_file.name)


def flatten_project_files_for_ai(input_file, plan_file, execution_file, tasks_file, doc_file):
    plan_units = units_from_file(plan_file.id)
    execution_units = units_from_file(execution_file.id)
    tasks_units = units_from_file(tasks_file.id)
    input_units = units_from_file(input_file.id)
    return {
        "input": flatten_file_by_parts_for_ai(input_units, input_file.name),
        "plan": flatten_file_by_parts_for_ai(plan_units, plan_file.name),
        "execution": flatten_file_by_parts_for_ai(
            execution_units, execution_file.name
        ),
        "tasks": flatten_file_by_parts_for_ai(tasks_units, tasks_file.name),
        "documentation": flatten_doc_file_for_ai(doc_file),
        "plan_parts": extract_part_names(plan_units),
        "execution_parts": extract_part_names(execution_units),
        "tasks_parts": extract_part_names(tasks_units),
    }


def units_from_doc_table(doc_file):
    blocks = (
        Block.query.filter_by(file_id=doc_file.id)
        .filter(Block.archived_at.is_(None))
        .order_by(Block.order_index, Block.id)
        .all()
    )
    units = []
    for block in blocks:
        if block.type != "table":
            continue
        rows = (block.content or {}).get("rows") or []
        for index, row in enumerate(rows):
            if not isinstance(row, list):
                continue
            cells = [str(cell).strip() for cell in row]
            if not any(cells):
                continue
            text = " | ".join(cell for cell in cells if cell)
            units.append(
                {
                    "id": f"table:{block.id}:row:{index}",
                    "kind": "table_row",
                    "text": text,
                    "block_id": block.id,
                    "row_index": index,
                }
            )
    return units


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
