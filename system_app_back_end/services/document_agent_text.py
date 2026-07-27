"""Deterministic agent text serialization for v3 documents."""

from __future__ import annotations

import re
from datetime import datetime
from typing import Any

from models import InformationPiece, ObjectEmbed, Task, db
from services.document_v3 import new_id, parse_document, serialize_document
from services.task_list_order import tasks_for_list

_TASK_LIST_RE = re.compile(
    r"\[TASK_LIST id=\"(\d+)\"]\s*(.*?)\s*\[/TASK_LIST]",
    re.DOTALL | re.IGNORECASE,
)
_INFO_RE = re.compile(
    r"\[INFO id=\"(\d+)\"]\s*(.*?)\s*\[/INFO]",
    re.DOTALL | re.IGNORECASE,
)
_IMAGE_RE = re.compile(r'\[IMAGE id="(\d+)"(?: caption="([^"]*)")?]', re.IGNORECASE)
_GRAPH_RE = re.compile(r'\[GRAPH id="(\d+)"(?: title="([^"]*)")?]', re.IGNORECASE)
_BULLET_LIST_RE = re.compile(
    r"\[BULLET_LIST]\s*(.*?)\s*\[/BULLET_LIST]",
    re.DOTALL | re.IGNORECASE,
)
_ORDERED_LIST_RE = re.compile(
    r"\[ORDERED_LIST]\s*(.*?)\s*\[/ORDERED_LIST]",
    re.DOTALL | re.IGNORECASE,
)
_TABLE_RE = re.compile(
    r"\[TABLE]\s*(.*?)\s*\[/TABLE]",
    re.DOTALL | re.IGNORECASE,
)
_TASK_LINE_RE = re.compile(r"^-\s*\[( |x|X)\]\s*(.*)$")
_BULLET_ITEM_RE = re.compile(r"^(\s*)[-*]\s+(.*)$")
_ORDERED_ITEM_RE = re.compile(r"^(\s*)\d+[\.\)]\s+(.*)$")

_SPECIAL_MARKERS = (
    "[TASK_LIST",
    "[INFO",
    "[IMAGE",
    "[GRAPH",
    "[BULLET_LIST",
    "[ORDERED_LIST",
    "[TABLE]",
)


def _escape_cell(text: str) -> str:
    return text.replace("\\", "\\\\").replace("\t", "\\t")


def _unescape_cell(text: str) -> str:
    out: list[str] = []
    i = 0
    while i < len(text):
        if text[i] == "\\" and i + 1 < len(text):
            nxt = text[i + 1]
            if nxt == "t":
                out.append("\t")
                i += 2
                continue
            if nxt == "\\":
                out.append("\\")
                i += 2
                continue
        out.append(text[i])
        i += 1
    return "".join(out)


def _split_table_row(line: str) -> list[str]:
    cells: list[str] = []
    current: list[str] = []
    i = 0
    while i < len(line):
        if line[i] == "\\" and i + 1 < len(line) and line[i + 1] == "t":
            current.append("\t")
            i += 2
            continue
        if line[i] == "\\" and i + 1 < len(line) and line[i + 1] == "\\":
            current.append("\\")
            i += 2
            continue
        if line[i] == "\t":
            cells.append("".join(current))
            current = []
            i += 1
            continue
        current.append(line[i])
        i += 1
    cells.append("".join(current))
    return [_unescape_cell(c) for c in cells]


def _list_block_type(block: dict[str, Any]) -> str:
    block_type = block.get("type")
    if block_type in {"bullet_list", "ordered_list"}:
        return block_type
    if block_type == "list":
        style = block.get("list_style") or "bullet"
        return "ordered_list" if style in {"numbered", "ordered"} else "bullet_list"
    return "bullet_list"


def _list_body(block: dict[str, Any]) -> str:
    list_type = _list_block_type(block)
    lines: list[str] = []
    for i, item in enumerate(block.get("items") or []):
        if not isinstance(item, dict):
            continue
        indent = "  " * int(item.get("indent") or 0)
        text = str(item.get("text") or "")
        if list_type == "ordered_list":
            lines.append(f"{indent}{i + 1}. {text}")
        else:
            lines.append(f"{indent}- {text}")
    return "\n".join(lines)


def _block_plain_text(block: dict[str, Any]) -> str:
    block_type = block.get("type")
    if block_type == "paragraph":
        return str(block.get("text") or "")
    if block_type == "heading":
        level = int(block.get("level") or 1)
        prefix = "#" * max(1, min(level, 6))
        return f"{prefix} {block.get('text') or ''}".rstrip()
    if block_type in {"list", "bullet_list", "ordered_list"}:
        body = _list_body(block)
        if not body:
            return ""
        tag = "ORDERED_LIST" if _list_block_type(block) == "ordered_list" else "BULLET_LIST"
        return f"[{tag}]\n{body}\n[/{tag}]"
    if block_type == "table":
        rows = block.get("rows") or []
        row_lines: list[str] = []
        for row in rows:
            if not isinstance(row, list):
                continue
            cells = [
                _escape_cell(
                    str(cell.get("text") if isinstance(cell, dict) else cell or "")
                )
                for cell in row
            ]
            row_lines.append("\t".join(cells))
        if not row_lines:
            return ""
        return "[TABLE]\n" + "\n".join(row_lines) + "\n[/TABLE]"
    return ""


def load_objects_by_id(file_id: int) -> dict[int, dict[str, Any]]:
    embeds = ObjectEmbed.query.filter_by(file_id=file_id).all()
    by_id: dict[int, dict[str, Any]] = {}
    for embed in embeds:
        tasks = tasks_for_list(embed.task_list_id) if embed.task_list_id else None
        info = (
            db.session.get(InformationPiece, embed.information_id)
            if embed.information_id
            else None
        )
        data = embed.to_dict(
            tasks=[t.to_dict() for t in tasks] if tasks is not None else None,
            information=info.to_dict() if info is not None else None,
        )
        by_id[embed.id] = data
    return by_id


def document_to_agent_text(
    body: str | None,
    *,
    objects_by_id: dict[int, dict[str, Any]] | None = None,
) -> str:
    doc = parse_document(body)
    objects_by_id = objects_by_id or {}
    lines: list[str] = []

    inline_types = {"paragraph", "heading", "list", "bullet_list", "ordered_list", "table"}
    for block in doc["blocks"]:
        block_type = block.get("type")
        if block_type in inline_types:
            text = _block_plain_text(block)
            if text:
                lines.append(text)
            continue
        if block_type != "embed":
            continue
        object_id = block.get("object_id")
        if object_id is None:
            legacy = block.get("_legacy") or {}
            if legacy.get("type") == "image":
                lines.append(f'[IMAGE url="{legacy.get("url", "")}"]')
            elif legacy.get("type") == "graph":
                lines.append("[GRAPH]")
            continue

        obj = objects_by_id.get(int(object_id), {})
        obj_type = obj.get("type")
        if obj_type == "task_list":
            lines.append(_task_list_section(int(object_id), obj))
        elif obj_type == "info":
            info = obj.get("information") or {}
            body_text = str(info.get("body") or info.get("title") or "")
            section = [f'[INFO id="{object_id}"]']
            if body_text:
                section.append(body_text)
            section.append("[/INFO]")
            lines.append("\n".join(section))
        elif obj_type == "image":
            payload = obj.get("payload") or {}
            caption = payload.get("caption") or payload.get("url") or ""
            lines.append(f'[IMAGE id="{object_id}" caption="{caption}"]')
        elif obj_type == "graph":
            payload = obj.get("payload") or {}
            title = payload.get("title") or ""
            lines.append(f'[GRAPH id="{object_id}" title="{title}"]')

    return "\n\n".join(line for line in lines if line is not None)


def _task_list_section(object_id: int, obj: dict[str, Any]) -> str:
    tasks = obj.get("tasks") or []
    active = [t for t in tasks if t.get("status") != "done"]
    done = [t for t in tasks if t.get("status") == "done"]
    lines = [f'[TASK_LIST id="{object_id}"]', "ACTIVE:"]
    for task in sorted(active, key=lambda t: (t.get("list_order_index", 0), t.get("id", 0))):
        lines.append(f"- [ ] {task.get('title', '')}")
    lines.append("DONE:")
    for task in sorted(done, key=lambda t: (t.get("list_order_index", 0), t.get("id", 0))):
        lines.append(f"- [x] {task.get('title', '')}")
    lines.append("[/TASK_LIST]")
    return "\n".join(lines)


def parse_agent_text(text: str) -> dict[str, Any]:
    """Parse agent text into structured blocks and object payloads."""
    blocks: list[dict[str, Any]] = []
    object_updates: dict[int, dict[str, Any]] = {}
    remaining = text
    pos = 0

    while pos < len(remaining):
        next_special = _find_next_special(remaining, pos)
        if next_special is None:
            chunk = remaining[pos:].strip()
            if chunk:
                blocks.extend(_text_to_blocks(chunk))
            break
        if next_special > pos:
            chunk = remaining[pos:next_special].strip()
            if chunk:
                blocks.extend(_text_to_blocks(chunk))

        matched = False
        for pattern, handler in (
            (_TASK_LIST_RE, _parse_task_list),
            (_INFO_RE, _parse_info),
            (_IMAGE_RE, _parse_image_marker),
            (_GRAPH_RE, _parse_graph_marker),
            (_BULLET_LIST_RE, _parse_bullet_list),
            (_ORDERED_LIST_RE, _parse_ordered_list),
            (_TABLE_RE, _parse_table),
        ):
            match = pattern.match(remaining, next_special)
            if match:
                block, update = handler(match)
                if block:
                    if isinstance(block, list):
                        blocks.extend(block)
                    else:
                        blocks.append(block)
                if update:
                    object_updates.update(update)
                pos = match.end()
                matched = True
                break
        if not matched:
            pos = next_special + 1

    return {"blocks": blocks, "object_updates": object_updates}


def apply_agent_text(
    body: str | None,
    agent_text: str,
    *,
    known_object_ids: set[int],
) -> tuple[dict[str, Any], dict[int, dict[str, Any]], list[str]]:
    """Parse agent text into a document tree. Return (doc, object_updates, errors)."""
    current = parse_document(body)
    parsed = parse_agent_text(agent_text)
    errors: list[str] = []

    referenced_ids = set(parsed["object_updates"].keys())
    for block in parsed["blocks"]:
        if block.get("type") == "embed" and block.get("object_id") is not None:
            referenced_ids.add(int(block["object_id"]))

    for object_id in referenced_ids:
        if object_id not in known_object_ids:
            errors.append(f"unknown object id: {object_id}")

    if errors:
        return current, {}, errors

    current_embeds = {
        int(b["object_id"]): b
        for b in current["blocks"]
        if b.get("type") == "embed" and b.get("object_id") is not None
    }
    for object_id in current_embeds:
        if object_id not in referenced_ids:
            errors.append(f"missing object id {object_id} in agent text — preserved")

    if errors:
        return current, {}, errors

    doc = {"version": 3, "blocks": parsed["blocks"]}
    return doc, parsed["object_updates"], []


def apply_object_updates(
    file_id: int,
    object_updates: dict[int, dict[str, Any]],
) -> list[str]:
    """Apply parsed object payload updates for a file. Returns error strings."""
    errors: list[str] = []
    for object_id, update in object_updates.items():
        embed = ObjectEmbed.query.filter_by(id=object_id, file_id=file_id).first()
        if embed is None:
            errors.append(f"object {object_id} not found on file {file_id}")
            continue
        update_type = update.get("type")
        if update_type == "task_list":
            _sync_task_list(embed, update.get("tasks") or [])
        elif update_type == "info":
            _sync_info(embed, update.get("body") or "")
        elif update_type in {"image", "graph"}:
            payload = update.get("payload") or {}
            embed.payload = {**(embed.payload or {}), **payload}
        else:
            errors.append(f"unsupported object update type: {update_type}")
    return errors


def _sync_task_list(embed: ObjectEmbed, tasks_data: list[dict[str, Any]]) -> None:
    if not embed.task_list_id:
        return
    existing = tasks_for_list(embed.task_list_id)
    now = datetime.utcnow()
    for task in existing:
        task.archived_at = now
    for i, item in enumerate(tasks_data):
        db.session.add(
            Task(
                task_list_id=embed.task_list_id,
                title=str(item.get("title") or ""),
                status=str(item.get("status") or "active"),
                list_order_index=int(item.get("list_order_index", i)),
            )
        )


def _sync_info(embed: ObjectEmbed, body: str) -> None:
    if not embed.information_id:
        return
    info = db.session.get(InformationPiece, embed.information_id)
    if info is None:
        return
    info.body = body


def agent_text_from_document_json(
    document_json: str | None,
    *,
    file_id: int | None = None,
    objects_by_id: dict[int, dict[str, Any]] | None = None,
) -> str:
    if objects_by_id is None and file_id is not None:
        objects_by_id = load_objects_by_id(file_id)
    return document_to_agent_text(document_json, objects_by_id=objects_by_id)


def apply_agent_text_to_file(
    file_id: int,
    current_document_json: str | None,
    agent_text: str,
    *,
    known_object_ids: set[int],
) -> tuple[str | None, dict[int, dict[str, Any]], list[str]]:
    """Return (serialized document_json or None on error, object_updates, errors)."""
    doc, object_updates, errors = apply_agent_text(
        current_document_json,
        agent_text,
        known_object_ids=known_object_ids,
    )
    if errors:
        return None, {}, errors
    return serialize_document(doc), object_updates, []


def _find_next_special(text: str, start: int) -> int | None:
    indices = []
    for marker in _SPECIAL_MARKERS:
        idx = text.find(marker, start)
        if idx >= 0:
            indices.append(idx)
    return min(indices) if indices else None


def _text_to_blocks(text: str) -> list[dict[str, Any]]:
    blocks: list[dict[str, Any]] = []
    for part in text.split("\n\n"):
        stripped = part.strip()
        if not stripped:
            continue
        if stripped.startswith("#"):
            level = 0
            while level < len(stripped) and stripped[level] == "#":
                level += 1
            blocks.append(
                {
                    "id": new_id("b"),
                    "type": "heading",
                    "level": max(1, min(level, 6)),
                    "text": stripped[level:].lstrip(),
                    "spans": [],
                }
            )
        else:
            blocks.append(
                {
                    "id": new_id("b"),
                    "type": "paragraph",
                    "text": stripped,
                    "spans": [],
                }
            )
    return blocks


def _parse_list_items(body: str, *, ordered: bool) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    for line in body.splitlines():
        if not line.strip():
            continue
        if ordered:
            match = _ORDERED_ITEM_RE.match(line)
        else:
            match = _BULLET_ITEM_RE.match(line)
        if not match:
            continue
        leading = len(match.group(1))
        indent = leading // 2
        text = match.group(2)
        items.append(
            {
                "id": new_id("li"),
                "text": text,
                "indent": indent,
                "spans": [],
            }
        )
    if not items:
        items.append({"id": new_id("li"), "text": "", "indent": 0, "spans": []})
    return items


def _parse_bullet_list(match: re.Match) -> tuple[dict | None, dict[int, dict]]:
    body = match.group(1)
    return (
        {
            "id": new_id("b"),
            "type": "bullet_list",
            "items": _parse_list_items(body, ordered=False),
        },
        {},
    )


def _parse_ordered_list(match: re.Match) -> tuple[dict | None, dict[int, dict]]:
    body = match.group(1)
    return (
        {
            "id": new_id("b"),
            "type": "ordered_list",
            "items": _parse_list_items(body, ordered=True),
        },
        {},
    )


def _parse_table(match: re.Match) -> tuple[dict | None, dict[int, dict]]:
    body = match.group(1).strip()
    rows: list[list[dict[str, Any]]] = []
    for line in body.splitlines():
        if not line.strip():
            continue
        cells = _split_table_row(line.rstrip("\n"))
        rows.append([{"text": cell, "spans": []} for cell in cells])
    if not rows:
        rows = [[{"text": "", "spans": []}, {"text": "", "spans": []}]]
    max_cols = max(len(row) for row in rows)
    normalized = []
    for row in rows:
        padded = row + [{"text": "", "spans": []}] * (max_cols - len(row))
        normalized.append(padded[:max_cols])
    return (
        {"id": new_id("b"), "type": "table", "rows": normalized},
        {},
    )


def _parse_task_list(match: re.Match) -> tuple[dict | None, dict[int, dict]]:
    object_id = int(match.group(1))
    body = match.group(2)
    tasks: list[dict[str, Any]] = []
    section = "active"
    order = 0
    for line in body.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        upper = stripped.upper()
        if upper == "ACTIVE:":
            section = "active"
            continue
        if upper == "DONE:":
            section = "done"
            continue
        task_match = _TASK_LINE_RE.match(stripped)
        if not task_match:
            continue
        checked = task_match.group(1).lower() == "x"
        tasks.append(
            {
                "title": task_match.group(2),
                "status": "done" if checked else "active",
                "list_order_index": order,
            }
        )
        order += 1
    return (
        {"id": new_id("b"), "type": "embed", "object_id": object_id},
        {object_id: {"type": "task_list", "tasks": tasks}},
    )


def _parse_info(match: re.Match) -> tuple[dict | None, dict[int, dict]]:
    object_id = int(match.group(1))
    body = match.group(2).strip()
    return (
        {"id": new_id("b"), "type": "embed", "object_id": object_id},
        {object_id: {"type": "info", "body": body}},
    )


def _parse_image_marker(match: re.Match) -> tuple[dict | None, dict[int, dict]]:
    object_id = int(match.group(1))
    caption = match.group(2) or ""
    return (
        {"id": new_id("b"), "type": "embed", "object_id": object_id},
        {object_id: {"type": "image", "payload": {"caption": caption}}},
    )


def _parse_graph_marker(match: re.Match) -> tuple[dict | None, dict[int, dict]]:
    object_id = int(match.group(1))
    title = match.group(2) or ""
    return (
        {"id": new_id("b"), "type": "embed", "object_id": object_id},
        {object_id: {"type": "graph", "payload": {"title": title}}},
    )
