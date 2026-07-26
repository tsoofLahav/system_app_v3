"""Deterministic agent text serialization for v3 documents."""

from __future__ import annotations

import re
from typing import Any

from services.document_v3 import parse_document

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
_TASK_LINE_RE = re.compile(r"^-\s*\[( |x|X)\]\s*(.*)$")


def _block_plain_text(block: dict[str, Any]) -> str:
    block_type = block.get("type")
    if block_type == "paragraph":
        return str(block.get("text") or "")
    if block_type == "heading":
        level = int(block.get("level") or 1)
        prefix = "#" * max(1, min(level, 6))
        return f"{prefix} {block.get('text') or ''}".rstrip()
    if block_type == "list":
        lines = []
        list_style = block.get("list_style") or "bullet"
        for i, item in enumerate(block.get("items") or []):
            indent = "  " * int(item.get("indent") or 0)
            text = str(item.get("text") or "")
            if list_style == "numbered":
                lines.append(f"{indent}{i + 1}. {text}")
            else:
                lines.append(f"{indent}- {text}")
        return "\n".join(lines)
    if block_type == "table":
        rows = block.get("rows") or []
        return "\n".join(
            "\t".join(str(cell.get("text") if isinstance(cell, dict) else cell or "") for cell in row)
            for row in rows
            if isinstance(row, list)
        )
    return ""


def document_to_agent_text(
    body: str | None,
    *,
    objects_by_id: dict[int, dict[str, Any]] | None = None,
) -> str:
    doc = parse_document(body)
    objects_by_id = objects_by_id or {}
    lines: list[str] = []

    for block in doc["blocks"]:
        block_type = block.get("type")
        if block_type in {"paragraph", "heading", "list", "table"}:
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
                lines.append(f"[IMAGE url=\"{legacy.get('url', '')}\"]")
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
            lines.append(f'[INFO id="{object_id}"]')
            if body_text:
                lines.append(body_text)
            lines.append(f"[/INFO]")
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
        ):
            match = pattern.match(remaining, next_special)
            if match:
                block, update = handler(match)
                if block:
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
) -> tuple[dict[str, Any], list[str]]:
    """Merge agent text into document; return (doc, errors). Never drop unknown objects."""
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
        return current, errors

    current_embeds = {
        int(b["object_id"]): b
        for b in current["blocks"]
        if b.get("type") == "embed" and b.get("object_id") is not None
    }
    for object_id in current_embeds:
        if object_id not in referenced_ids:
            errors.append(f"missing object id {object_id} in agent text — preserved")

    if errors:
        return current, errors

    return {"version": 3, "blocks": parsed["blocks"]}, []


def _find_next_special(text: str, start: int) -> int | None:
    indices = []
    for marker in ("[TASK_LIST", "[INFO", "[IMAGE", "[GRAPH"):
        idx = text.find(marker, start)
        if idx >= 0:
            indices.append(idx)
    return min(indices) if indices else None


def _text_to_blocks(text: str) -> list[dict[str, Any]]:
    from services.document_v3 import new_id

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
                    "level": max(1, level),
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
        {"id": f"b{object_id}", "type": "embed", "object_id": object_id},
        {object_id: {"type": "task_list", "tasks": tasks}},
    )


def _parse_info(match: re.Match) -> tuple[dict | None, dict[int, dict]]:
    object_id = int(match.group(1))
    body = match.group(2).strip()
    return (
        {"id": f"b{object_id}", "type": "embed", "object_id": object_id},
        {object_id: {"type": "info", "body": body}},
    )


def _parse_image_marker(match: re.Match) -> tuple[dict | None, dict[int, dict]]:
    object_id = int(match.group(1))
    caption = match.group(2) or ""
    return (
        {"id": f"b{object_id}", "type": "embed", "object_id": object_id},
        {object_id: {"type": "image", "payload": {"caption": caption}}},
    )


def _parse_graph_marker(match: re.Match) -> tuple[dict | None, dict[int, dict]]:
    object_id = int(match.group(1))
    title = match.group(2) or ""
    return (
        {"id": f"b{object_id}", "type": "embed", "object_id": object_id},
        {object_id: {"type": "graph", "payload": {"title": title}}},
    )
