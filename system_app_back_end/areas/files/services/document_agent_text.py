"""Agent text projection over editor-text (v4) documents.

Editor text (SoT) stores pointer-only object markers. Agent text expands those
pointers with live object payloads. See document_marker_text.py / DOCUMENT_TEXT.md.
"""

from __future__ import annotations

import re
from datetime import datetime
from typing import Any

from models import InformationPiece, ObjectEmbed, Task, db
from areas.files.services import document_marker_text as marker_text
from areas.files.services.document_v3 import new_id, parse_document, serialize_document
from areas.objects.services.task_list_order import tasks_for_list

# Shared marker emit helpers (single home: document_marker_text).
SPACER_N_MIN = marker_text.SPACER_N_MIN
SPACER_N_MAX = marker_text.SPACER_N_MAX
_SPACER_RE = marker_text._SPACER_RE
_escape_cell = marker_text._escape_cell
_list_block_type = marker_text._list_block_type
_list_body = marker_text._list_body
_spacer_marker = marker_text._spacer_marker
_append_spacer = marker_text._append_spacer

_TASK_LIST_RE = re.compile(
    r"\[TASK_LIST id=\"(\d+)\"]\s*(.*?)\s*\[/TASK_LIST]",
    re.DOTALL | re.IGNORECASE,
)
_INFO_RE = re.compile(
    r"\[INFO id=\"(\d+)\"]\s*(.*?)\s*\[/INFO]",
    re.DOTALL | re.IGNORECASE,
)
_IMAGE_RE = re.compile(
    r'\[IMAGE id="(\d+)"'
    r'(?: caption="([^"]*)")?'
    r'(?: url="([^"]*)")?'
    r']',
    re.IGNORECASE,
)
# Block form (frozen). Legacy single-line `[GRAPH id="N" title="…"]` still matches.
_GRAPH_RE = re.compile(
    r'\[GRAPH id="(\d+)"'
    r'(?:(?:\s+chartType="([^"]*)")|(?:\s+title="([^"]*)"))*'
    r'\]'
    r'(?:\s*(.*?)\s*\[/GRAPH])?',
    re.DOTALL | re.IGNORECASE,
)
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
    "[SPACER",
    "[TASK_LIST",
    "[INFO",
    "[IMAGE",
    "[GRAPH",
    "[BULLET_LIST",
    "[ORDERED_LIST",
    "[TABLE]",
)


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


def _append_paragraph_agent_parts(lines: list[str], text: str) -> None:
    """Emit paragraph text; ``\\n\\n`` gaps become ``[SPACER]`` markers."""
    marker_text._append_paragraph_parts(lines, text)


def _empty_paragraph() -> dict[str, Any]:
    return {"id": new_id("b"), "type": "paragraph", "text": "", "spans": []}


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
        # Pass model instances — ObjectEmbed.to_dict serializes them.
        data = embed.to_dict(tasks=tasks, information=info)
        by_id[embed.id] = data
    return by_id


_POINTER_LINE_RE = re.compile(
    r'\[(INFO|TASK_LIST|IMAGE|GRAPH|EMBED)\s+id="(\d+)"\s*\]',
    re.IGNORECASE,
)


def editor_text_to_agent_text(
    editor_body: str | None,
    *,
    objects_by_id: dict[int, dict[str, Any]] | None = None,
) -> str:
    """Expand pointer markers in editor text into agent fences."""
    objects_by_id = objects_by_id or {}
    text = marker_text.editor_text_body(editor_body)

    def replace_pointer(match: re.Match) -> str:
        tag = match.group(1).upper()
        object_id = int(match.group(2))
        obj = objects_by_id.get(object_id, {})
        obj_type = obj.get("type") or {
            "INFO": "info",
            "TASK_LIST": "task_list",
            "IMAGE": "image",
            "GRAPH": "graph",
            "EMBED": "",
        }.get(tag, "")
        if obj_type == "task_list":
            return _task_list_section(object_id, obj)
        if obj_type == "info":
            return _info_section(object_id, obj)
        if obj_type == "image":
            return _image_section(object_id, obj)
        if obj_type == "graph":
            return _graph_section(object_id, obj)
        # Unknown / missing object — leave a bare pointer so apply can reject.
        return marker_text.pointer_line(object_id, obj_type or None)

    expanded = _POINTER_LINE_RE.sub(replace_pointer, text)
    if expanded and all(_SPACER_RE.fullmatch(line.strip()) for line in expanded.split("\n\n")):
        return ""
    return expanded


def document_to_agent_text(
    body: str | None,
    *,
    objects_by_id: dict[int, dict[str, Any]] | None = None,
) -> str:
    """Project stored body (v4 editor text or legacy v3 JSON) to agent text."""
    objects_by_id = objects_by_id or {}
    editor = marker_text.ensure_editor_text(body, objects_by_id=objects_by_id)
    return editor_text_to_agent_text(editor, objects_by_id=objects_by_id)


def _attr_escape(value: str) -> str:
    return value.replace('"', "'").replace("\n", " ")


def _info_section(object_id: int, obj: dict[str, Any]) -> str:
    """Frozen shape: first line title, remaining lines body."""
    info = obj.get("information") or {}
    title = str(info.get("title") or "").strip()
    body = str(info.get("body") or "").strip()
    section = [f'[INFO id="{object_id}"]', title]
    if body:
        section.append(body)
    section.append("[/INFO]")
    return "\n".join(section)


def _image_section(object_id: int, obj: dict[str, Any]) -> str:
    """Frozen shape: caption + optional url/path ref."""
    payload = obj.get("payload") or {}
    caption = str(payload.get("caption") or "").strip()
    ref = str(payload.get("url") or payload.get("path") or "").strip()
    attrs = [f'id="{object_id}"']
    if caption:
        attrs.append(f'caption="{_attr_escape(caption)}"')
    if ref:
        attrs.append(f'url="{_attr_escape(ref)}"')
    return f'[IMAGE {" ".join(attrs)}]'


def _graph_section(object_id: int, obj: dict[str, Any]) -> str:
    """Frozen shape: optional chartType; two-row labels/values table; optional colors row."""
    payload = obj.get("payload") or {}
    labels = [str(x) for x in (payload.get("labels") or [])]
    values = [str(x) for x in (payload.get("values") or [])]
    colors_raw = payload.get("colors")
    if not colors_raw and payload.get("color"):
        colors_raw = [payload.get("color")]
    colors = [str(x) for x in (colors_raw or [])] if colors_raw else []
    chart_type = str(
        payload.get("chartType") or payload.get("chart_type") or ""
    ).strip()

    n = max(len(labels), len(values), len(colors), 1)
    labels = (labels + [""] * n)[:n]
    values = (values + [""] * n)[:n]

    open_tag = f'[GRAPH id="{object_id}"'
    if chart_type:
        open_tag += f' chartType="{_attr_escape(chart_type)}"'
    open_tag += "]"

    lines = [
        open_tag,
        "\t".join(_escape_cell(c) for c in labels),
        "\t".join(_escape_cell(c) for c in values),
    ]
    if colors:
        colors = (colors + [""] * n)[:n]
        lines.append("\t".join(_escape_cell(c) for c in colors))
    lines.append("[/GRAPH]")
    return "\n".join(lines)


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
            (_SPACER_RE, _parse_spacer),
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


def agent_text_to_editor_text(
    agent_text: str,
    *,
    known_object_ids: set[int],
    current_body: str | None = None,
) -> tuple[str | None, dict[int, dict[str, Any]], list[str]]:
    """Collapse agent text to pointer-only editor text + object_updates."""
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
        return None, {}, errors

    current_ids = marker_text.embed_ids_in_text(
        marker_text.editor_text_body(current_body)
    )
    # Also accept legacy v3 current bodies.
    if not current_ids and current_body and not marker_text.is_editor_text(current_body):
        current_doc = parse_document(current_body)
        current_ids = {
            int(b["object_id"])
            for b in current_doc["blocks"]
            if b.get("type") == "embed" and b.get("object_id") is not None
        }

    for object_id in current_ids:
        if object_id not in referenced_ids:
            errors.append(f"missing object id {object_id} in agent text — preserved")

    if errors:
        return None, {}, errors

    # Rebuild editor text from parsed blocks — embeds as pointers only.
    lines: list[str] = []
    for block in parsed["blocks"]:
        block_type = block.get("type")
        if block_type == "paragraph":
            _append_paragraph_agent_parts(lines, str(block.get("text") or ""))
            continue
        if block_type in {
            "heading",
            "list",
            "bullet_list",
            "ordered_list",
            "table",
        }:
            text = _block_plain_text(block)
            if text:
                lines.append(text)
            continue
        if block_type == "embed" and block.get("object_id") is not None:
            oid = int(block["object_id"])
            update = parsed["object_updates"].get(oid) or {}
            lines.append(marker_text.pointer_line(oid, update.get("type")))
    if lines and all(_SPACER_RE.fullmatch(line.strip()) for line in lines):
        return marker_text.empty_editor_text(), parsed["object_updates"], []
    body = "\n\n".join(line for line in lines if line is not None)
    return marker_text.wrap_editor_text(body), parsed["object_updates"], []


def apply_agent_text(
    body: str | None,
    agent_text: str,
    *,
    known_object_ids: set[int],
) -> tuple[dict[str, Any], dict[int, dict[str, Any]], list[str]]:
    """Legacy API: return a v3-shaped doc for older callers; prefer apply_agent_text_to_file."""
    editor, object_updates, errors = agent_text_to_editor_text(
        agent_text,
        known_object_ids=known_object_ids,
        current_body=body,
    )
    if errors or editor is None:
        current = parse_document(body)
        return current, {}, errors
    doc = marker_text.v3_from_editor_text_lossy(editor)
    return doc, object_updates, []


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
            _sync_info(embed, update)
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


def _sync_info(embed: ObjectEmbed, update: dict[str, Any]) -> None:
    if not embed.information_id:
        return
    info = db.session.get(InformationPiece, embed.information_id)
    if info is None:
        return
    if "title" in update:
        info.title = str(update.get("title") or "")
    if "body" in update:
        info.body = str(update.get("body") or "")


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
    """Return (wrapped editor text or None on error, object_updates, errors)."""
    editor, object_updates, errors = agent_text_to_editor_text(
        agent_text,
        known_object_ids=known_object_ids,
        current_body=current_document_json,
    )
    if errors or editor is None:
        return None, {}, errors
    return editor, object_updates, []


def _find_next_special(text: str, start: int) -> int | None:
    indices = []
    for marker in _SPECIAL_MARKERS:
        idx = text.find(marker, start)
        if idx >= 0:
            indices.append(idx)
    return min(indices) if indices else None


def _text_to_blocks(text: str) -> list[dict[str, Any]]:
    """Plain text → paragraphs/headings; empty ``\\n\\n`` runs → empty paragraphs."""
    blocks: list[dict[str, Any]] = []
    pending_empty = 0

    def flush_empty() -> None:
        nonlocal pending_empty
        for _ in range(pending_empty):
            blocks.append(_empty_paragraph())
        pending_empty = 0

    for part in text.split("\n\n"):
        stripped = part.strip()
        if not stripped:
            pending_empty += 1
            continue
        flush_empty()
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
    flush_empty()
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


def _parse_spacer(match: re.Match) -> tuple[list[dict[str, Any]], dict[int, dict]]:
    """Agent ``[SPACER]`` → empty paragraph blocks (no special document type)."""
    raw_n = match.group(1)
    n = int(raw_n) if raw_n else 1
    n = max(SPACER_N_MIN, min(n, SPACER_N_MAX))
    return [_empty_paragraph() for _ in range(n)], {}


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
    """First line = title, remaining = body. Single-line legacy = body only."""
    object_id = int(match.group(1))
    content = (match.group(2) or "").strip("\n")
    update: dict[str, Any] = {"type": "info"}
    if "\n" in content:
        title, _, rest = content.partition("\n")
        update["title"] = title.strip()
        update["body"] = rest.lstrip("\n")
    else:
        # Legacy body-only fence — do not clobber title.
        update["body"] = content.strip()
    return (
        {"id": new_id("b"), "type": "embed", "object_id": object_id},
        {object_id: update},
    )


def _parse_image_marker(match: re.Match) -> tuple[dict | None, dict[int, dict]]:
    object_id = int(match.group(1))
    caption = match.group(2) or ""
    url = match.group(3) or ""
    payload: dict[str, Any] = {}
    if caption:
        payload["caption"] = caption
    if url:
        payload["url"] = url
    return (
        {"id": new_id("b"), "type": "embed", "object_id": object_id},
        {object_id: {"type": "image", "payload": payload}},
    )


def _parse_graph_marker(match: re.Match) -> tuple[dict | None, dict[int, dict]]:
    object_id = int(match.group(1))
    chart_type = (match.group(2) or "").strip()
    legacy_title = (match.group(3) or "").strip()
    body = (match.group(4) or "").strip()
    payload: dict[str, Any] = {}
    if chart_type:
        payload["chartType"] = chart_type
    elif legacy_title and not body:
        # Legacy single-line marker used title= as a display label.
        payload["title"] = legacy_title

    data_lines = [ln for ln in body.splitlines() if ln.strip()]
    if data_lines:
        labels = _split_table_row(data_lines[0])
        values = _split_table_row(data_lines[1]) if len(data_lines) > 1 else []
        payload["labels"] = labels
        payload["values"] = values
        if len(data_lines) > 2:
            payload["colors"] = _split_table_row(data_lines[2])

    return (
        {"id": new_id("b"), "type": "embed", "object_id": object_id},
        {object_id: {"type": "graph", "payload": payload}},
    )
