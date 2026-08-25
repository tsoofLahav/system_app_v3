"""Editor-text (v4 marker) document — source of truth for file bodies.

See frontend DOCUMENT_TEXT.md / files AREA.md. Object markers are pointers only;
agent text expands them via document_agent_text.
"""

from __future__ import annotations

import re
from typing import Any

from areas.files.services.document_v3 import (
    new_id,
    parse_document,
    serialize_document,
)

DOCUMENT_TEXT_HEADER = "%%system_app_document v4"
SPACER_N_MIN = 1
SPACER_N_MAX = 12

_SPACER_RE = re.compile(
    r'\[SPACER(?:\s+n="(\d+)")?\s*\]',
    re.IGNORECASE,
)
_POINTER_RE = re.compile(
    r'^\[(INFO|TASK_LIST|IMAGE|GRAPH|TABLE|EMBED)\s+id="(\d+)"\s*\]\s*$',
    re.IGNORECASE | re.MULTILINE,
)
_POINTER_LINE_RE = re.compile(
    r'\[(INFO|TASK_LIST|IMAGE|GRAPH|TABLE|EMBED)\s+id="(\d+)"\s*\]',
    re.IGNORECASE,
)
_POINTER_ID_RE = re.compile(
    r'(\[(?:TABLE|GRAPH|INFO|TASK_LIST|IMAGE|EMBED)\b[^\]]*?\bid=")(\d+)(")',
    re.IGNORECASE,
)

_TYPE_TO_TAG = {
    "info": "INFO",
    "task_list": "TASK_LIST",
    "image": "IMAGE",
    "graph": "GRAPH",
    "table": "TABLE",
}


def is_editor_text(body: str | None) -> bool:
    raw = (body or "").lstrip()
    return raw.startswith(DOCUMENT_TEXT_HEADER)


def strip_header(body: str | None) -> str:
    raw = body or ""
    if not is_editor_text(raw):
        return raw
    rest = raw.split("\n", 1)
    return rest[1] if len(rest) > 1 else ""


def wrap_editor_text(text: str) -> str:
    body = text if text is not None else ""
    # Avoid double-wrapping.
    if is_editor_text(body):
        body = strip_header(body)
    return f"{DOCUMENT_TEXT_HEADER}\n{body}"


def empty_editor_text() -> str:
    return wrap_editor_text("")


def pointer_line(object_id: int, object_type: str | None = None) -> str:
    tag = _TYPE_TO_TAG.get(str(object_type or ""), "EMBED")
    return f'[{tag} id="{int(object_id)}"]'


def embed_ids_in_text(text: str) -> set[int]:
    return {int(m.group(2)) for m in _POINTER_LINE_RE.finditer(text or "")}


def rewrite_pointer_ids(text: str, id_map: dict[int, int]) -> str:
    """Replace pointer ``id="N"`` values using ``id_map`` (old → new)."""

    def repl(match: re.Match[str]) -> str:
        old_id = int(match.group(2))
        new_id = id_map.get(old_id, old_id)
        return f"{match.group(1)}{new_id}{match.group(3)}"

    return _POINTER_ID_RE.sub(repl, text or "")


def iter_embed_pointers(text: str):
    """Yield ``(tag, object_id)`` for each pointer line, in document order."""
    for match in _POINTER_RE.finditer(text or ""):
        yield match.group(1).lower(), int(match.group(2))


def _escape_cell(text: str) -> str:
    """Escape cell text for agent/table rows joined by visible ``\\t``.

    In-cell tab becomes ``\\\\t`` so it does not collide with the ``\\t`` separator.
    """
    return text.replace("\\", "\\\\").replace("\t", "\\\\t")


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


def _spacer_marker(n: int) -> str:
    n = max(SPACER_N_MIN, min(int(n), SPACER_N_MAX))
    return f'[SPACER n="{n}"]'


def _append_spacer(lines: list[str], n: int = 1) -> None:
    n = max(SPACER_N_MIN, min(int(n), SPACER_N_MAX))
    if lines:
        match = _SPACER_RE.fullmatch(lines[-1].strip())
        if match:
            prev = int(match.group(1) or 1)
            lines[-1] = _spacer_marker(prev + n)
            return
    lines.append(_spacer_marker(n))


def _append_paragraph_parts(lines: list[str], text: str) -> None:
    if text == "":
        _append_spacer(lines, 1)
        return
    parts = text.split("\n\n")
    pending_empty = 0
    seen_text = False
    for part in parts:
        if not part.strip():
            pending_empty += 1
            continue
        if seen_text:
            _append_spacer(lines, 2 * pending_empty + 1)
            pending_empty = 0
        elif pending_empty:
            _append_spacer(lines, pending_empty)
            pending_empty = 0
        lines.append(part)
        seen_text = True
    if pending_empty:
        _append_spacer(lines, pending_empty)


def _structure_block_text(block: dict[str, Any]) -> str:
    block_type = block.get("type")
    if block_type == "paragraph":
        return ""  # handled via _append_paragraph_parts
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


def migrate_v3_json_to_editor_text(
    body: str | None,
    *,
    objects_by_id: dict[int, dict[str, Any]] | None = None,
) -> str:
    """Convert v3 JSON (or plain legacy) to wrapped editor text. Spans dropped."""
    if is_editor_text(body):
        return wrap_editor_text(strip_header(body))

    objects_by_id = objects_by_id or {}
    doc = parse_document(body)
    lines: list[str] = []

    for block in doc["blocks"]:
        block_type = block.get("type")
        if block_type == "paragraph":
            _append_paragraph_parts(lines, str(block.get("text") or ""))
            continue
        if block_type in {
            "heading",
            "list",
            "bullet_list",
            "ordered_list",
            "table",
        }:
            text = _structure_block_text(block)
            if text:
                lines.append(text)
            continue
        if block_type != "embed":
            continue
        object_id = block.get("object_id")
        if object_id is None:
            continue
        oid = int(object_id)
        obj_type = (objects_by_id.get(oid) or {}).get("type")
        lines.append(pointer_line(oid, obj_type if isinstance(obj_type, str) else None))

    if lines and all(_SPACER_RE.fullmatch(line.strip()) for line in lines):
        return empty_editor_text()
    return wrap_editor_text("\n\n".join(line for line in lines if line is not None))


def ensure_editor_text(
    body: str | None,
    *,
    objects_by_id: dict[int, dict[str, Any]] | None = None,
) -> str:
    """Return wrapped editor text; migrate v3 JSON when needed."""
    if body is None or not str(body).strip():
        return empty_editor_text()
    if is_editor_text(body):
        return wrap_editor_text(strip_header(body))
    # Heuristic: JSON object with version/blocks → migrate.
    stripped = str(body).lstrip()
    if stripped.startswith("{") or stripped.startswith("["):
        return migrate_v3_json_to_editor_text(body, objects_by_id=objects_by_id)
    # Bare marker text without header.
    return wrap_editor_text(str(body))


def editor_text_body(body: str | None) -> str:
    """Unwrapped body for editing / agent expand."""
    return strip_header(ensure_editor_text(body))


def insert_embed_pointer(
    body: str | None,
    object_id: int,
    *,
    object_type: str | None = None,
    block_index: int | None = None,
) -> str:
    """Insert a pointer as its own block (\\n\\n-separated)."""
    text = editor_text_body(body)
    pointer = pointer_line(object_id, object_type)
    if not text.strip():
        return wrap_editor_text(pointer)

    parts = _split_top_level_blocks(text)
    index = len(parts) if block_index is None else max(0, min(int(block_index), len(parts)))
    parts.insert(index, pointer)
    return wrap_editor_text("\n\n".join(parts))


def remove_embed_pointers(body: str | None, object_id: int) -> str:
    text = editor_text_body(body)
    oid = int(object_id)
    parts = [
        p
        for p in _split_top_level_blocks(text)
        if not _is_pointer_for(p, oid)
    ]
    return wrap_editor_text("\n\n".join(parts))


def move_embed_pointer(
    body: str | None,
    object_id: int,
    *,
    gap_index: int,
) -> str:
    """Move pointer for object_id to top-level gap (0 = before first block)."""
    text = editor_text_body(body)
    oid = int(object_id)
    parts = _split_top_level_blocks(text)
    current = next((i for i, p in enumerate(parts) if _is_pointer_for(p, oid)), None)
    if current is None:
        return wrap_editor_text(text)
    pointer = parts.pop(current).strip()
    # Adjust gap after removal.
    gap = int(gap_index)
    if current < gap:
        gap -= 1
    gap = max(0, min(gap, len(parts)))
    parts.insert(gap, pointer)
    return wrap_editor_text("\n\n".join(parts))


def _split_top_level_blocks(text: str) -> list[str]:
    """Split on \\n\\n but keep fenced regions intact."""
    if not text:
        return []
    # Simple split is OK: fences themselves contain single \\n, not \\n\\n between
    # open/close in normal serialization. Nested \\n\\n inside fences is rare;
    # agent/editor serializers use single newlines inside fences.
    parts = re.split(r"\n\n+", text)
    return [p for p in parts if p is not None]


def _is_pointer_for(block: str, object_id: int) -> bool:
    match = _POINTER_RE.match(block.strip())
    return bool(match and int(match.group(2)) == int(object_id))


def validate_editor_text(
    body: str | None,
    known_object_ids: set[int] | None = None,
) -> None:
    text = ensure_editor_text(body)
    if known_object_ids is None:
        return
    for oid in embed_ids_in_text(strip_header(text)):
        if oid not in known_object_ids:
            raise ValueError(f"unknown object id in document: {oid}")


# Re-export for callers that still build v3 briefly during migration tests.
def v3_from_editor_text_lossy(body: str | None) -> dict[str, Any]:
    """Best-effort editor text → v3 blocks (pointers as embeds). Spans empty.

    Used only where legacy code still needs a block tree (promote, anchors).
    """
    from areas.files.services import document_agent_text as agent

    # Expand with empty objects so pointers stay as short INFO-less… actually
    # parse_agent_text expects expanded or structure markers. Pointer-only lines
    # are not in parse_agent_text as standalone — they look like plain text.
    # Convert pointers to temporary embed-only agent form the parser understands:
    text = editor_text_body(body)
    # Turn pointer lines into minimal expanded forms parse_agent_text accepts.
    def _expand_pointer(match: re.Match) -> str:
        tag = match.group(1).upper()
        oid = match.group(2)
        if tag == "INFO":
            return f'[INFO id="{oid}"]\n\n[/INFO]'
        if tag == "TASK_LIST":
            return (
                f'[TASK_LIST id="{oid}"]\nACTIVE:\nDONE:\n[/TASK_LIST]'
            )
        if tag == "IMAGE":
            return f'[IMAGE id="{oid}"]'
        if tag == "GRAPH":
            return f'[GRAPH id="{oid}"]\n\n[/GRAPH]'
        if tag == "TABLE":
            return f'[TABLE id="{oid}"]\n\n[/TABLE]'
        return f'[INFO id="{oid}"]\n\n[/INFO]'

    expanded = _POINTER_LINE_RE.sub(_expand_pointer, text)
    parsed = agent.parse_agent_text(expanded)
    return {"version": 3, "blocks": parsed["blocks"]}
