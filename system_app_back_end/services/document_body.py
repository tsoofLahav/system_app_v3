"""Document body marker helpers for v2 inline embeds."""

from __future__ import annotations

import re

TASK_MARKER = re.compile(r"^\{\{task:(\d+)\}\}$")
INFO_MARKER = re.compile(r"^\{\{info:(\d+)\}\}$")


def marker_for(type_: str, entity_id: int) -> str:
    if type_ == "task":
        return f"{{{{task:{entity_id}}}}}"
    if type_ == "information":
        return f"{{{{info:{entity_id}}}}}"
    raise ValueError(f"Unknown embed type: {type_}")


def insert_marker(body: str, marker: str, line: int | None = None) -> str:
    lines = body.splitlines(keepends=True)
    if not lines and not body:
        lines = []
    insert_at = len(lines) if line is None else max(0, min(line, len(lines)))
    token = marker if marker.endswith("\n") else f"{marker}\n"
    lines.insert(insert_at, token)
    return "".join(lines)


def remove_marker(body: str, marker: str) -> str:
    lines = []
    for raw in body.splitlines(keepends=True):
        stripped = raw.rstrip("\n\r")
        if stripped == marker:
            continue
        lines.append(raw)
    return "".join(lines)


def parse_markers(body: str) -> list[dict]:
    """Return ordered marker descriptors with line indices."""
    found: list[dict] = []
    for index, raw in enumerate(body.splitlines()):
        stripped = raw.strip()
        task_match = TASK_MARKER.match(stripped)
        if task_match:
            found.append(
                {
                    "kind": "marker",
                    "type": "task",
                    "entity_id": int(task_match.group(1)),
                    "line": index,
                    "marker": stripped,
                }
            )
            continue
        info_match = INFO_MARKER.match(stripped)
        if info_match:
            found.append(
                {
                    "kind": "marker",
                    "type": "information",
                    "entity_id": int(info_match.group(1)),
                    "line": index,
                    "marker": stripped,
                }
            )
    return found


def sync_anchors(body: str, objects: list) -> None:
    markers = {m["marker"]: m for m in parse_markers(body)}
    for obj in objects:
        marker = None
        if obj.type == "task" and obj.task_id:
            marker = marker_for("task", obj.task_id)
        elif obj.type == "information" and obj.information_id:
            marker = marker_for("information", obj.information_id)
        if marker and marker in markers:
            obj.anchor = markers[marker]
