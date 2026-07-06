"""Write daily process documentation entries into doc table and progress graph."""

from __future__ import annotations

import re
from datetime import datetime
from zoneinfo import ZoneInfo

from sqlalchemy.orm.attributes import flag_modified

from models import Block, Topic, db
from services.automation_definitions import get_definition, resolve_files_by_bindings
from services.automation_dispatcher import dispatch_file_changed
from services.automation_params import normalize_params
from services.automation_schedule import DEFAULT_AUTOMATION_TIMEZONE

_ISO_DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
_DEFAULT_TABLE_HEADER = ["Date", "Entry"]
_DEFAULT_GRAPH_CONTENT = {
    "chart_type": "line",
    "title": "Progress",
    "labels": [],
    "values": [],
    "palette_index": 0,
}


def submit_process_documentation_input(
    *,
    topic_id: int,
    text: str,
    grade: int,
    date: str | None = None,
    timezone: str | None = None,
) -> dict:
    topic = db.session.get(Topic, int(topic_id))
    if topic is None:
        raise ValueError("topic not found")

    definition = get_definition(key="process_documentation_input")
    if definition is None:
        raise ValueError("process_documentation_input definition not found")

    params = normalize_params(None, definition.key, definition.action_type)
    files_by_role = resolve_files_by_bindings(topic.id, params)
    doc_file = files_by_role.get("doc")
    if doc_file is None:
        raise ValueError(f"Cannot document process '{topic.name}': missing doc file.")

    cleaned_text = (text or "").strip()
    if not cleaned_text:
        raise ValueError("text is required")

    grade_value = int(grade)
    if grade_value < 1 or grade_value > 10:
        raise ValueError("grade must be between 1 and 10")

    entry_date = (date or "").strip() or _today_in_timezone(timezone)
    if not _ISO_DATE_RE.match(entry_date):
        raise ValueError("date must be YYYY-MM-DD")

    blocks = _active_blocks(doc_file.id)
    table_block = _ensure_block(
        doc_file,
        blocks,
        "table",
        {"rows": [_DEFAULT_TABLE_HEADER[:], ["", ""]]},
        insert_before_types=("graph", "text"),
    )
    graph_block = _ensure_block(
        doc_file,
        blocks,
        "graph",
        dict(_DEFAULT_GRAPH_CONTENT),
        insert_before_types=("text",),
    )

    _insert_table_row(table_block, entry_date, cleaned_text)
    _append_graph_point(graph_block, entry_date, float(grade_value))

    db.session.flush()
    dispatch_file_changed(doc_file.id, "process_documentation_input", {"topic_id": topic.id})

    return {
        "topic_id": topic.id,
        "doc_file_id": doc_file.id,
        "table_block_id": table_block.id,
        "graph_block_id": graph_block.id,
        "date": entry_date,
        "grade": grade_value,
    }


def _today_in_timezone(timezone: str | None) -> str:
    tz_name = (timezone or "").strip() or DEFAULT_AUTOMATION_TIMEZONE
    try:
        tz = ZoneInfo(tz_name)
    except Exception:
        tz = ZoneInfo(DEFAULT_AUTOMATION_TIMEZONE)
    return datetime.now(tz).date().isoformat()


def _active_blocks(file_id):
    return (
        Block.query.filter_by(file_id=file_id)
        .filter(Block.archived_at.is_(None))
        .order_by(Block.order_index, Block.id)
        .all()
    )


def _ensure_block(file, blocks, block_type, default_content, insert_before_types=()):
    for block in blocks:
        if block.type == block_type:
            return block

    insert_index = len(blocks)
    for index, block in enumerate(blocks):
        if block.type in insert_before_types:
            insert_index = index
            break

    for block in blocks:
        if block.order_index is not None and block.order_index >= insert_index:
            block.order_index = (block.order_index or 0) + 1

    new_block = Block(
        file_id=file.id,
        type=block_type,
        content=dict(default_content),
        order_index=insert_index,
    )
    db.session.add(new_block)
    db.session.flush()
    return new_block


def _insert_table_row(table_block, entry_date: str, text: str) -> None:
    content = dict(table_block.content or {})
    rows = content.get("rows")
    if not isinstance(rows, list):
        rows = []

    normalized_rows = []
    for row in rows:
        if isinstance(row, list):
            normalized_rows.append([str(cell) for cell in row])
        else:
            normalized_rows.append([str(row)])

    if not normalized_rows:
        normalized_rows = [_DEFAULT_TABLE_HEADER[:], ["", ""]]
    elif len(normalized_rows[0]) < 2:
        first = normalized_rows[0]
        normalized_rows[0] = [
            str(first[0]) if first else "",
            str(first[1]) if len(first) > 1 else "",
        ]

    insert_index = 1 if _looks_like_header_row(normalized_rows[0]) else 0
    normalized_rows.insert(insert_index, [entry_date, text])

    table_block.content = {"rows": normalized_rows}
    flag_modified(table_block, "content")


def _looks_like_header_row(row: list[str]) -> bool:
    if not row:
        return False
    first = str(row[0]).strip()
    if _ISO_DATE_RE.match(first):
        return False
    second = str(row[1]).strip() if len(row) > 1 else ""
    return bool(first) or bool(second)


def _append_graph_point(graph_block, entry_date: str, grade: float) -> None:
    content = dict(graph_block.content or {})
    labels = content.get("labels")
    values = content.get("values")
    if not isinstance(labels, list):
        labels = []
    if not isinstance(values, list):
        values = []

    next_labels = [str(item) for item in labels]
    next_values: list[float] = []
    for item in values:
        if isinstance(item, (int, float)):
            next_values.append(float(item))
        else:
            next_values.append(float(str(item)) if str(item).strip() else 0.0)

    next_labels.append(entry_date)
    next_values.append(grade)

    content["chart_type"] = "line"
    if not str(content.get("title") or "").strip():
        content["title"] = _DEFAULT_GRAPH_CONTENT["title"]
    content["labels"] = next_labels
    content["values"] = next_values
    if "palette_index" not in content:
        content["palette_index"] = 0

    graph_block.content = content
    flag_modified(graph_block, "content")
