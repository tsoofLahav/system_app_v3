"""Agent text projection over editor-text (v4) documents.

Editor text (SoT) stores pointer-only object markers. Agent text expands those
pointers with live object payloads. See document_marker_text.py / DOCUMENT_TEXT.md.
"""

from __future__ import annotations

import re
from datetime import datetime
from typing import Any

from models import InformationPiece, ObjectEmbed, Task, TaskList, db
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
    r'\[TASK_LIST id="(\d+)"'
    r'(?: title="([^"]*)")?'
    r'\]\s*(.*?)\s*\[/TASK_LIST]',
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
    r'(?: width="([^"]*)")?'
    r'\]'
    r'(?:\n((?:url="[^"]*"(?: caption="[^"]*")?(?: width="[^"]*")?\n)*)\[/IMAGE])?',
    re.IGNORECASE,
)
_IMAGE_PANE_LINE_RE = re.compile(
    r'url="([^"]*)"(?: caption="([^"]*)")?(?: width="([^"]*)")?',
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
    r'\[TABLE(?:\s+id="(\d+)")?\]\s*(.*?)\s*\[/TABLE]',
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
    "[TABLE",
)

# Markers that must open and close. An unmatched one is not a structure at all:
# the parser below falls through and keeps the marker as literal text, so it
# would land in the user's document as characters. Validation rejects that.
_FENCED_MARKERS = (
    "TASK_LIST",
    "INFO",
    "GRAPH",
    "BULLET_LIST",
    "ORDERED_LIST",
    "TABLE",
)
_MARKER_LINE_RE = re.compile(
    r"^\[(/?)\s*([A-Z][A-Z0-9_]*)\b([^\]]*)\]$",
    re.IGNORECASE,
)
# Lists are pure structure — an id or any other attribute makes them unparsable.
_ATTRIBUTE_FREE_MARKERS = ("BULLET_LIST", "ORDERED_LIST")


def validate_agent_text_markers(text: str) -> list[str]:
    """Errors for structure markers that would degrade into literal text.

    Catches the common agent slips: opening a fence and never closing it,
    closing one that was never opened, and putting attributes on a list.
    Unknown marker names are left alone — they are not our language, so they
    are legitimately just text.
    """
    errors: list[str] = []
    stack: list[tuple[str, int]] = []

    for number, raw in enumerate(text.split("\n"), start=1):
        match = _MARKER_LINE_RE.match(raw.strip())
        if not match:
            continue
        closing = bool(match.group(1))
        name = match.group(2).upper()
        attributes = match.group(3).strip()
        if name not in _FENCED_MARKERS:
            continue

        # Inside a fence only its own closer counts; the rest is content.
        if stack and not (closing and name == stack[-1][0]):
            continue

        if closing:
            if not stack:
                errors.append(
                    f"line {number}: [/{name}] closes a marker that was never "
                    "opened"
                )
                continue
            stack.pop()
            continue

        if name in _ATTRIBUTE_FREE_MARKERS and attributes:
            errors.append(
                f"line {number}: [{name}] takes no attributes — write "
                f"[{name}] on its own line"
            )
        # Opened either way, so its closer is not reported as a second fault.
        stack.append((name, number))

    for name, number in stack:
        errors.append(
            f"line {number}: [{name}] is never closed — add [/{name}] on its "
            "own line, or edit the lines inside the existing one"
        )
    return errors


def _unescape_cell(text: str) -> str:
    """Undo ``_escape_cell``: ``\\\\t`` → tab, ``\\\\`` → ``\\``, legacy ``\\t`` → tab."""
    out: list[str] = []
    i = 0
    while i < len(text):
        if text[i] == "\\" and i + 1 < len(text):
            if text[i + 1] == "\\" and i + 2 < len(text) and text[i + 2] == "t":
                out.append("\t")
                i += 3
                continue
            if text[i + 1] == "\\":
                out.append("\\")
                i += 2
                continue
            if text[i + 1] == "t":
                out.append("\t")
                i += 2
                continue
        out.append(text[i])
        i += 1
    return "".join(out)


def _split_table_row(line: str) -> list[str]:
    """Split a table/graph row on visible ``\\t`` (or raw tab for older text)."""
    cells: list[str] = []
    current: list[str] = []
    i = 0
    while i < len(line):
        if line[i] == "\\" and i + 1 < len(line) and line[i + 1] == "\\":
            # Keep ``\\`` / ``\\t`` for unescape (do not treat as separator).
            current.append("\\")
            current.append("\\")
            i += 2
            if i < len(line) and line[i] == "t":
                current.append("t")
                i += 1
            continue
        if line[i] == "\\" and i + 1 < len(line) and line[i + 1] == "t":
            cells.append(_unescape_cell("".join(current)))
            current = []
            i += 2
            continue
        if line[i] == "\t":
            cells.append(_unescape_cell("".join(current)))
            current = []
            i += 1
            continue
        current.append(line[i])
        i += 1
    cells.append(_unescape_cell("".join(current)))
    return cells


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
            row_lines.append("\\t".join(cells))
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
        task_list = (
            db.session.get(TaskList, embed.task_list_id)
            if embed.task_list_id
            else None
        )
        # Pass model instances — ObjectEmbed.to_dict serializes them.
        data = embed.to_dict(task_list=task_list, tasks=tasks, information=info)
        by_id[embed.id] = data
    return by_id


_POINTER_LINE_RE = re.compile(
    r'\[(INFO|TASK_LIST|IMAGE|GRAPH|TABLE|EMBED)\s+id="(\d+)"\s*\]',
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
            "TABLE": "table",
            "EMBED": "",
        }.get(tag, "")
        if obj_type == "task_list":
            return _task_list_section(object_id, obj)
        if obj_type == "info":
            return _info_section(object_id, obj)
        if obj_type == "image":
            return _image_section(object_id, obj)
        if obj_type in {"graph", "table"} or (obj.get("type") in {"graph", "table"}):
            return _table_or_graph_section(object_id, obj)
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
    """Frozen shape: caption + optional url/path ref; extra panes as fence lines."""
    from areas.objects.services.image_payload import panes_of

    payload = obj.get("payload") or {}
    panes = panes_of(payload if isinstance(payload, dict) else {})
    first = panes[0] if panes else {"url": "", "caption": ""}
    caption = str(first.get("caption") or "").strip()
    ref = str(first.get("url") or "").strip()
    attrs = [f'id="{object_id}"']
    if caption:
        attrs.append(f'caption="{_attr_escape(caption)}"')
    if ref:
        attrs.append(f'url="{_attr_escape(ref)}"')
    width = payload.get("width") if isinstance(payload, dict) else None
    if width is not None and width != "":
        attrs.append(f'width="{_attr_escape(str(width))}"')
    opener = f'[IMAGE {" ".join(attrs)}]'
    extras = panes[1:]
    if not extras:
        return opener
    lines = [opener]
    for pane in extras:
        extra = f'url="{_attr_escape(str(pane.get("url") or ""))}"'
        cap = str(pane.get("caption") or "").strip()
        if cap:
            extra += f' caption="{_attr_escape(cap)}"'
        lines.append(extra)
    lines.append("[/IMAGE]")
    return "\n".join(lines)


def _table_or_graph_section(object_id: int, obj: dict[str, Any]) -> str:
    """Table object: GRAPH fence when chart quality is on, else TABLE fence."""
    from areas.objects.services.table_payload import (
        chart_enabled,
        chart_meta,
        normalize_table_payload,
        rows_to_labels_values,
    )

    payload = normalize_table_payload(obj.get("payload") or {})
    if chart_enabled(payload):
        return _graph_section_normalized(object_id, payload)
    return _table_section_normalized(object_id, payload)


def _graph_section_normalized(object_id: int, payload: dict[str, Any]) -> str:
    """Agent GRAPH fence: chartType + labels/values (+ optional colors)."""
    from areas.objects.services.table_payload import chart_meta, rows_to_labels_values

    labels, values = rows_to_labels_values(payload)
    meta = chart_meta(payload)
    chart_type = str(meta.get("chartType") or "").strip()
    colors = list(meta.get("colors") or [])

    n = max(len(labels), len(values), len(colors), 1)
    labels = (labels + [""] * n)[:n]
    values = (values + [""] * n)[:n]

    open_tag = f'[GRAPH id="{object_id}"'
    if chart_type:
        open_tag += f' chartType="{_attr_escape(chart_type)}"'
    open_tag += "]"

    lines = [
        open_tag,
        "\\t".join(_escape_cell(c) for c in labels),
        "\\t".join(_escape_cell(c) for c in values),
    ]
    if colors:
        colors = (colors + [""] * n)[:n]
        lines.append("\\t".join(_escape_cell(c) for c in colors))
    lines.append("[/GRAPH]")
    return "\n".join(lines)


def _table_section_normalized(object_id: int, payload: dict[str, Any]) -> str:
    rows = payload.get("rows") or []
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
        row_lines.append("\\t".join(cells))
    if not row_lines:
        row_lines = ["\\t"]
    return (
        f'[TABLE id="{object_id}"]\n'
        + "\n".join(row_lines)
        + "\n[/TABLE]"
    )


def _task_list_section(object_id: int, obj: dict[str, Any]) -> str:
    tasks = obj.get("tasks") or []
    active = [t for t in tasks if t.get("status") == "active"]
    pending = [t for t in tasks if t.get("status") == "pending"]
    inactive = [t for t in tasks if t.get("status") == "inactive"]
    done = [t for t in tasks if t.get("status") == "done"]
    other = [
        t
        for t in tasks
        if t.get("status") not in {"active", "pending", "inactive", "done"}
    ]
    active = active + other
    task_list = obj.get("task_list") if isinstance(obj.get("task_list"), dict) else {}
    title = str(task_list.get("title") or obj.get("title") or "")
    open_tag = f'[TASK_LIST id="{object_id}"'
    if title:
        open_tag += f' title="{_attr_escape(title)}"'
    open_tag += "]"
    lines = [open_tag, "ACTIVE:"]
    for task in sorted(active, key=lambda t: (t.get("list_order_index", 0), t.get("id", 0))):
        lines.append(f"- [ ] {task.get('title', '')}")
    if pending:
        lines.append("PENDING:")
        for task in sorted(pending, key=lambda t: (t.get("list_order_index", 0), t.get("id", 0))):
            lines.append(f"- [ ] {task.get('title', '')}")
    if inactive:
        lines.append("INACTIVE:")
        for task in sorted(inactive, key=lambda t: (t.get("list_order_index", 0), t.get("id", 0))):
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
    marker_errors = validate_agent_text_markers(agent_text)
    if marker_errors:
        return None, {}, marker_errors

    parsed = parse_agent_text(agent_text)
    errors: list[str] = []

    referenced_ids = set(parsed["object_updates"].keys())
    for block in parsed["blocks"]:
        if block.get("type") == "embed" and block.get("object_id") is not None:
            referenced_ids.add(int(block["object_id"]))

    for object_id in referenced_ids:
        if object_id not in known_object_ids:
            errors.append(f"unknown object id: {object_id}")

    for block in parsed["blocks"]:
        if block.get("type") == "table":
            errors.append(
                'TABLE fence requires id="…" — copy ids from open_file; '
                "inline [TABLE]…[/TABLE] without id is not allowed on write"
            )

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
            title = update["title"] if "title" in update else None
            _sync_task_list(embed, update.get("tasks") or [], title=title)
        elif update_type == "info":
            _sync_info(embed, update)
        elif update_type in {"image", "graph", "table"}:
            payload = update.get("payload") or {}
            if update_type == "image":
                embed.payload = {**(embed.payload or {}), **payload}
            else:
                from areas.objects.services.table_payload import normalize_table_payload

                embed.type = "table"
                embed.payload = normalize_table_payload(payload)
        else:
            errors.append(f"unsupported object update type: {update_type}")
    return errors


def _sync_task_list(
    embed: ObjectEmbed,
    tasks_data: list[dict[str, Any]],
    *,
    title: str | None = None,
) -> None:
    if not embed.task_list_id:
        return
    if title is not None:
        task_list = db.session.get(TaskList, embed.task_list_id)
        if task_list is not None:
            task_list.title = str(title)
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
    from areas.objects.services.table_payload import normalize_table_payload

    object_id_raw = match.group(1)
    body = (match.group(2) or "").strip()
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
    payload = normalize_table_payload({"rows": normalized})
    if object_id_raw:
        object_id = int(object_id_raw)
        return (
            {"id": new_id("b"), "type": "embed", "object_id": object_id},
            {
                object_id: {
                    "type": "table",
                    "payload": payload,
                }
            },
        )
    # Id-less fence — rejected on write in agent_text_to_editor_text.
    return (
        {"id": new_id("b"), "type": "table", "rows": normalized},
        {},
    )


def _parse_task_list(match: re.Match) -> tuple[dict | None, dict[int, dict]]:
    object_id = int(match.group(1))
    title_attr = match.group(2)
    body = match.group(3)
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
        if upper == "PENDING:":
            section = "pending"
            continue
        if upper == "INACTIVE:":
            section = "inactive"
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
                "status": "done" if checked else section,
                "list_order_index": order,
            }
        )
        order += 1
    update: dict[str, Any] = {"type": "task_list", "tasks": tasks}
    if title_attr is not None:
        update["title"] = title_attr
    return (
        {"id": new_id("b"), "type": "embed", "object_id": object_id},
        {object_id: update},
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
    caption = match.group(2)
    url = match.group(3)
    width_raw = match.group(4)
    extra_body = match.group(5)
    payload: dict[str, Any] = {}
    if caption is not None:
        payload["caption"] = caption
    if url is not None:
        payload["url"] = url
    if width_raw is not None and width_raw.strip():
        try:
            payload["width"] = float(width_raw.strip())
        except ValueError:
            payload["width"] = width_raw.strip()
    extras: list[dict[str, Any]] = []
    if extra_body:
        for raw in extra_body.splitlines():
            line = raw.strip()
            if not line:
                continue
            pane = _IMAGE_PANE_LINE_RE.fullmatch(line)
            if pane is None:
                continue
            extras.append(
                {
                    "url": pane.group(1) or "",
                    "caption": pane.group(2) or "",
                }
            )
    if extras:
        from areas.objects.services.image_payload import mirrored

        payload = mirrored(
            [
                {
                    "url": payload.get("url") or "",
                    "caption": payload.get("caption") or "",
                },
                *extras,
            ],
            width=payload.get("width"),
        )
    return (
        {"id": new_id("b"), "type": "embed", "object_id": object_id},
        {object_id: {"type": "image", "payload": payload}},
    )


def _parse_graph_marker(match: re.Match) -> tuple[dict | None, dict[int, dict]]:
    from areas.objects.services.table_payload import normalize_table_payload

    object_id = int(match.group(1))
    chart_type = (match.group(2) or "").strip()
    legacy_title = (match.group(3) or "").strip()
    body = (match.group(4) or "").strip()
    legacy: dict[str, Any] = {}
    if chart_type:
        legacy["chartType"] = chart_type
    elif legacy_title and not body:
        legacy["title"] = legacy_title

    data_lines = [ln for ln in body.splitlines() if ln.strip()]
    if data_lines:
        legacy["labels"] = _split_table_row(data_lines[0])
        legacy["values"] = (
            _split_table_row(data_lines[1]) if len(data_lines) > 1 else []
        )
        if len(data_lines) > 2:
            legacy["colors"] = _split_table_row(data_lines[2])

    payload = normalize_table_payload(legacy)
    return (
        {"id": new_id("b"), "type": "embed", "object_id": object_id},
        {object_id: {"type": "table", "payload": payload}},
    )
