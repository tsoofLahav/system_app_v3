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


_PART_KEY_RE = re.compile(r"[^a-z0-9\u0590-\u05FF]+")


def _part_key(title: str) -> str:
    return _PART_KEY_RE.sub("", (title or "").strip().lower())


def extract_log_sections(units):
    """Split input units into sections by header blocks."""
    sections = []
    current = None
    for unit in units:
        if unit.get("kind") == "header":
            if current is not None:
                sections.append(current)
            current = {
                "header": (unit.get("text") or "").strip(),
                "units": [unit],
            }
            continue
        if current is None:
            continue
        current["units"].append(unit)
    if current is not None:
        sections.append(current)
    return sections


def flatten_log_section(section):
    header = (section.get("header") or "").strip() or "(untitled)"
    lines = [f"=== LOG SECTION: {header} ==="]
    for unit in section.get("units") or []:
        text = (unit.get("text") or "").strip()
        if text:
            lines.append(f"[{unit['id']}] {text}")
    return "\n".join(lines).strip()


def flatten_log_sections_for_mapping(log_sections, max_excerpt_lines=3):
    lines = []
    for section in log_sections:
        header = (section.get("header") or "").strip() or "(untitled)"
        lines.append(f"SECTION: {header}")
        count = 0
        for unit in section.get("units") or []:
            if unit.get("kind") == "header":
                continue
            text = (unit.get("text") or "").strip()
            if not text:
                continue
            lines.append(f"  - {text}")
            count += 1
            if count >= max_excerpt_lines:
                break
        lines.append("")
    return "\n".join(lines).strip() or "(no sections)"


def slice_units_by_part(units, part_name):
    key = _part_key(part_name)
    if not key:
        return []
    result = []
    in_part = False
    for unit in units:
        if unit.get("kind") == "header":
            title = (unit.get("text") or "").strip()
            in_part = _part_key(title) == key
            if in_part:
                result.append(unit)
            continue
        if in_part:
            result.append(unit)
    return result


def last_unit_id(units):
    return units[-1]["id"] if units else None


def flatten_single_part_for_ai(units, file_title, part_name):
    slice_units = slice_units_by_part(units, part_name)
    lines = [f"=== {file_title.upper()} — PART: {part_name} ==="]
    if not slice_units:
        anchor = last_unit_id(units)
        lines.append("(this part does not exist in this file yet)")
        if anchor:
            lines.append(f"Anchor for add_after (last unit in file): [{anchor}]")
        return "\n".join(lines).strip()
    for unit in slice_units:
        text = (unit.get("text") or "").strip()
        if text:
            lines.append(f"[{unit['id']}] {text}")
    return "\n".join(lines).strip()


def build_part_removal_ops(units, part_name):
    return [
        {"op": "remove", "unit_id": unit["id"]}
        for unit in slice_units_by_part(units, part_name)
    ]


def list_plan_headers(plan_units):
    return extract_part_names(plan_units)


def numbered_plan_headers(plan_units):
    return [
        (index + 1, header)
        for index, header in enumerate(list_plan_headers(plan_units))
    ]


def format_numbered_plan_headers(plan_units):
    lines = [
        f"[{index}] {header}" for index, header in numbered_plan_headers(plan_units)
    ]
    return "\n".join(lines) or "(none)"


def resolve_plan_index(plan_units, plan_index):
    headers = list_plan_headers(plan_units)
    try:
        index = int(plan_index) - 1
    except (TypeError, ValueError):
        return ""
    if 0 <= index < len(headers):
        return headers[index]
    return ""


_PART_KEY_RE = re.compile(r"[^a-z0-9\u0590-\u05FF]+")
_REMOVAL_MARKERS = (
    "remove",
    "removed",
    "retire",
    "retired",
    "drop",
    "dropped",
    "deprecate",
    "deprecated",
    "discontinue",
    "discontinued",
    "no longer",
    "הסר",
    "הוסר",
    "הוצא",
    "בוטל",
    "הורד",
    "לא רלוונטי",
)


def _normalized_part_key(title: str) -> str:
    return _PART_KEY_RE.sub("", (title or "").strip().lower())


def log_explicitly_removes_part(part_name, log_sections):
    """True only when a log section clearly retires this plan part."""
    part_key = _normalized_part_key(part_name)
    if not part_key:
        return False
    for section in log_sections or []:
        header = (section.get("header") or "").strip()
        body = flatten_log_content(section)
        combined = f"{header}\n{body}".strip().lower()
        if not combined:
            continue
        if not any(marker in combined for marker in _REMOVAL_MARKERS):
            continue
        header_key = _normalized_part_key(header)
        if header_key and (header_key == part_key or part_key in header_key):
            return True
        if part_name.lower() in combined or part_key in _normalized_part_key(combined):
            return True
    return False


def filter_parts_to_remove(parts_to_remove, log_sections):
    return [
        part_name
        for part_name in parts_to_remove or []
        if log_explicitly_removes_part(part_name, log_sections)
    ]


def parse_header_map_instructions(result, plan_units, log_sections):
    """Turn sparse numbered instructions into part entries for orchestration."""
    content_parts = []
    parts_to_remove = []
    raw_instructions = []

    for entry in result.get("instructions") or []:
        if not isinstance(entry, dict):
            continue
        raw_instructions.append(entry)
        action = (entry.get("action") or "").strip().lower()
        if action == "edit":
            action = "update"

        if action == "remove":
            part_name = resolve_plan_index(plan_units, entry.get("plan_index"))
            if part_name and part_name not in parts_to_remove:
                parts_to_remove.append(part_name)
            continue

        if action == "update":
            part_name = resolve_plan_index(plan_units, entry.get("plan_index"))
            part_entry = {
                "part_name": part_name,
                "action": "update",
                "log_section_index": entry.get("log_section_index"),
                "plan_index": entry.get("plan_index"),
            }
            attach_mapped_log_content(part_entry, log_sections)
            if part_name and part_entry.get("log_content") is not None:
                content_parts.append(part_entry)
            continue

        if action == "create":
            part_entry = {
                "part_name": (entry.get("part_name") or "").strip(),
                "action": "create",
                "log_section_index": entry.get("log_section_index"),
            }
            attach_mapped_log_content(part_entry, log_sections)
            if not part_entry.get("part_name") and part_entry.get("log_header"):
                part_entry["part_name"] = part_entry["log_header"]
            if part_entry.get("part_name") and part_entry.get("log_content") is not None:
                content_parts.append(part_entry)

    return {
        "parts": content_parts,
        "parts_to_remove": parts_to_remove,
        "log_date": (result.get("log_date") or "").strip(),
        "instructions": raw_instructions,
    }


def list_log_sections_for_map(log_sections):
    lines = []
    for index, section in enumerate(log_sections):
        header = (section.get("header") or "").strip() or "(untitled)"
        lines.append(f"[{index}] {header}")
    return "\n".join(lines) or "(none)"


def flatten_log_content(section):
    lines = []
    for unit in section.get("units") or []:
        if unit.get("kind") == "header":
            continue
        text = (unit.get("text") or "").strip()
        if text:
            lines.append(text)
    return "\n".join(lines)


def attach_mapped_log_content(part_entry, log_sections):
    idx = part_entry.get("log_section_index")
    if idx is None:
        return part_entry
    try:
        idx = int(idx)
    except (TypeError, ValueError):
        return part_entry
    if 0 <= idx < len(log_sections):
        section = log_sections[idx]
        part_entry["log_header"] = (
            section.get("header") or part_entry.get("log_header") or ""
        )
        part_entry["log_content"] = flatten_log_content(section)
    return part_entry


def match_plan_header_exact(plan_units, part_name):
    key = _part_key(part_name)
    if not key:
        return ""
    for header in extract_part_names(plan_units):
        if _part_key(header) == key:
            return header
    return ""


def part_change_id_prefix(file_key, part_name):
    slug = _part_key(part_name) or "part"
    return f"{file_key}:{slug[:48]}"


def build_code_header_map(plan_units, log_sections):
    plan_headers = list_plan_headers(plan_units)
    plan_by_key = {_part_key(header): header for header in plan_headers}
    parts = []
    for index, section in enumerate(log_sections):
        log_header = (section.get("header") or "").strip()
        if not log_header:
            continue
        key = _part_key(log_header)
        if key in plan_by_key:
            parts.append(
                {
                    "part_name": plan_by_key[key],
                    "action": "update",
                    "log_section_index": index,
                    "log_header": log_header,
                }
            )
        else:
            parts.append(
                {
                    "part_name": log_header,
                    "action": "create",
                    "log_section_index": index,
                    "log_header": log_header,
                }
            )
    return parts


def resolve_plan_part_name(plan_units, part_name):
    key = _part_key(part_name)
    if not key:
        return (part_name or "").strip()
    headers = extract_part_names(plan_units)
    for header in headers:
        if _part_key(header) == key:
            return header
    for header in headers:
        header_key = _part_key(header)
        if header_key.startswith(key) or key.startswith(header_key):
            return header
    return (part_name or "").strip()


def extract_part_content_items(units, part_name):
    items = []
    for unit in slice_units_by_part(units, part_name):
        if unit.get("kind") == "header":
            continue
        text = (unit.get("text") or "").strip()
        if text:
            items.append(text)
    return items


def flatten_part_content_for_update(units, file_title, part_name):
    items = extract_part_content_items(units, part_name)
    lines = [f"=== {file_title.upper()} — PART: {part_name} ==="]
    if not items:
        lines.append("(empty)")
    else:
        for item in items:
            lines.append(f"- {item}")
    return "\n".join(lines)


def flatten_part_units_with_ids(units, part_name):
    slice_units = slice_units_by_part(units, part_name)
    lines = []
    for unit in slice_units:
        text = (unit.get("text") or "").strip()
        if text:
            lines.append(f"[{unit['id']}] {text}")
    return "\n".join(lines) or "(empty)"


def synthesize_create_preview_from_content(part_name, items, file_key):
    default_kind = "task" if file_key == "tasks" else "list_item"
    units = []
    index = 0
    for item in items or []:
        text = str(item).strip()
        if not text:
            continue
        units.append(
            {
                "id": f"preview:{file_key}:item:{index}",
                "kind": default_kind,
                "text": text,
                "part": part_name,
            }
        )
        index += 1
    return units


def synthesize_create_part_units(part_name, ops, file_key, anchor_unit=None):
    default_kind = "task" if file_key == "tasks" else "list_item"
    units = [
        {
            "id": f"preview:{file_key}:header",
            "kind": "header",
            "text": part_name,
            "part": part_name,
        }
    ]
    index = 0
    for op in ops or []:
        if (op.get("op") or "").strip().lower() != "add_after":
            continue
        text = (op.get("text") or "").strip()
        kind = (op.get("kind") or default_kind).strip()
        if kind == "header":
            continue
        if not text:
            continue
        units.append(
            {
                "id": f"preview:{file_key}:item:{index}",
                "kind": kind,
                "text": text,
                "part": part_name,
            }
        )
        index += 1
    if anchor_unit:
        anchor = dict(anchor_unit)
        anchor["part"] = part_name
        units.append(anchor)
    return units


def normalize_content_payload(content):
    if not isinstance(content, dict):
        return {"plan": [], "execution": [], "tasks": []}

    def _lines(key):
        raw = content.get(key) or []
        if not isinstance(raw, list):
            return []
        return [str(item).strip() for item in raw if str(item).strip()]

    return {
        "plan": _lines("plan"),
        "execution": _lines("execution"),
        "tasks": _lines("tasks"),
    }


def flatten_doc_recent_rows_for_ai(doc_file, max_rows=5):
    blocks = (
        Block.query.filter_by(file_id=doc_file.id)
        .filter(Block.archived_at.is_(None))
        .order_by(Block.order_index, Block.id)
        .all()
    )
    rows = []
    for block in blocks:
        if block.type != "table":
            continue
        for row in (block.content or {}).get("rows") or []:
            cells = [str(cell).strip() for cell in row if str(cell).strip()]
            if cells:
                rows.append(" | ".join(cells))
    recent = rows[-max_rows:] if max_rows else rows
    body = "\n".join(recent) if recent else "(no rows yet)"
    return f"=== RECENT DOCUMENTATION (last {len(recent)} rows) ===\n{body}".strip()


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
