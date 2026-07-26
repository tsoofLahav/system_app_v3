"""JSON document body codec for v2 rich files."""

from __future__ import annotations

import json
import re
import uuid
from typing import Any

DOCUMENT_VERSION = 1

NODE_TYPES = {
    "paragraph",
    "table",
    "list",
    "image",
    "graph",
    "object",
}

OBJECT_TYPES = {"task_list", "info"}

# Legacy line markers (v2 alpha)
_TASK_MARKER = re.compile(r"^\{\{task:(\d+)\}\}$")
_INFO_MARKER = re.compile(r"^\{\{info:(\d+)\}\}$")


def new_node_id() -> str:
    return f"n{uuid.uuid4().hex[:8]}"


def empty_document() -> dict[str, Any]:
    return {"version": DOCUMENT_VERSION, "nodes": []}


def empty_document_json() -> str:
    return serialize_document(empty_document())


def parse_document(body: str | None) -> dict[str, Any]:
    raw = body or ""
    if not raw.strip():
        return empty_document()
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return _migrate_plain_body(raw)
    if not isinstance(data, dict) or "nodes" not in data:
        return _migrate_plain_body(raw)
    nodes = data.get("nodes")
    if not isinstance(nodes, list):
        return _migrate_plain_body(raw)
    return {
        "version": int(data.get("version") or DOCUMENT_VERSION),
        "nodes": [_normalize_node(n) for n in nodes if isinstance(n, dict)],
    }


def serialize_document(doc: dict[str, Any]) -> str:
    normalized = {
        "version": int(doc.get("version") or DOCUMENT_VERSION),
        "nodes": [_normalize_node(n) for n in doc.get("nodes") or [] if isinstance(n, dict)],
    }
    return json.dumps(normalized, ensure_ascii=False, separators=(",", ":"))


def _normalize_node(node: dict[str, Any]) -> dict[str, Any]:
    node_type = node.get("type")
    if node_type not in NODE_TYPES:
        raise ValueError(f"unknown node type: {node_type}")
    normalized = {"id": str(node.get("id") or new_node_id()), "type": node_type}
    if node_type == "paragraph":
        normalized["text"] = str(node.get("text") or "")
        spans = node.get("spans")
        normalized["spans"] = spans if isinstance(spans, list) else []
    elif node_type == "table":
        rows = node.get("rows")
        normalized["rows"] = rows if isinstance(rows, list) else [["", ""]]
    elif node_type == "list":
        items = node.get("items")
        normalized["items"] = items if isinstance(items, list) else [""]
        normalized["list_style"] = node.get("list_style") or "bullet"
    elif node_type == "image":
        normalized["url"] = str(node.get("url") or "")
        if node.get("width") is not None:
            normalized["width"] = node["width"]
    elif node_type == "graph":
        labels = node.get("labels")
        values = node.get("values")
        normalized["labels"] = labels if isinstance(labels, list) else []
        normalized["values"] = values if isinstance(values, list) else []
    elif node_type == "object":
        object_type = node.get("object_type")
        if object_type not in OBJECT_TYPES:
            raise ValueError(f"unknown object_type: {object_type}")
        normalized["object_type"] = object_type
        normalized["object_id"] = int(node["object_id"])
    return normalized


def _migrate_plain_body(body: str) -> dict[str, Any]:
    nodes: list[dict[str, Any]] = []
    for line in body.splitlines():
        stripped = line.strip()
        task_match = _TASK_MARKER.match(stripped)
        if task_match:
            nodes.append(
                {
                    "id": new_node_id(),
                    "type": "object",
                    "object_type": "task_list",
                    "object_id": int(task_match.group(1)),
                }
            )
            continue
        info_match = _INFO_MARKER.match(stripped)
        if info_match:
            nodes.append(
                {
                    "id": new_node_id(),
                    "type": "object",
                    "object_type": "info",
                    "object_id": int(info_match.group(1)),
                }
            )
            continue
        if line or nodes:
            nodes.append(
                {
                    "id": new_node_id(),
                    "type": "paragraph",
                    "text": line,
                    "spans": [],
                }
            )
    if not nodes:
        nodes.append(
            {"id": new_node_id(), "type": "paragraph", "text": "", "spans": []}
        )
    return {"version": DOCUMENT_VERSION, "nodes": nodes}


def insert_node(
    body: str,
    node: dict[str, Any],
    *,
    index: int | None = None,
) -> str:
    doc = parse_document(body)
    nodes = doc["nodes"]
    insert_at = len(nodes) if index is None else max(0, min(index, len(nodes)))
    nodes.insert(insert_at, _normalize_node({**node, "id": node.get("id") or new_node_id()}))
    return serialize_document(doc)


def remove_node_by_id(body: str, node_id: str) -> str:
    doc = parse_document(body)
    doc["nodes"] = [n for n in doc["nodes"] if n.get("id") != node_id]
    return serialize_document(doc)


def remove_object_nodes(body: str, object_id: int) -> str:
    doc = parse_document(body)
    doc["nodes"] = [
        n
        for n in doc["nodes"]
        if not (
            n.get("type") == "object" and int(n.get("object_id") or 0) == object_id
        )
    ]
    return serialize_document(doc)


def move_node(body: str, node_id: str, new_index: int) -> str:
    doc = parse_document(body)
    nodes = doc["nodes"]
    current = next((i for i, n in enumerate(nodes) if n.get("id") == node_id), None)
    if current is None:
        return serialize_document(doc)
    node = nodes.pop(current)
    new_index = max(0, min(new_index, len(nodes)))
    nodes.insert(new_index, node)
    return serialize_document(doc)


def object_node_for(object_id: int, object_type: str, *, node_id: str | None = None) -> dict:
    return {
        "id": node_id or new_node_id(),
        "type": "object",
        "object_type": object_type,
        "object_id": object_id,
    }


def sync_object_anchors(body: str, objects: list) -> None:
    doc = parse_document(body)
    node_by_object: dict[int, dict] = {}
    for index, node in enumerate(doc["nodes"]):
        if node.get("type") != "object":
            continue
        object_id = node.get("object_id")
        if object_id is not None:
            node_by_object[int(object_id)] = {"kind": "node", "node_id": node["id"], "index": index}

    for obj in objects:
        hit = node_by_object.get(obj.id)
        if hit:
            obj.anchor = hit


def document_plain_text(body: str | None) -> str:
    doc = parse_document(body)
    lines: list[str] = []
    for node in doc["nodes"]:
        node_type = node.get("type")
        if node_type == "paragraph":
            text = str(node.get("text") or "")
            if text:
                lines.append(text)
        elif node_type == "table":
            rows = node.get("rows") or []
            for row in rows:
                if isinstance(row, list):
                    lines.append(" | ".join(str(c) for c in row))
        elif node_type == "list":
            items = node.get("items") or []
            for i, item in enumerate(items):
                prefix = f"{i + 1}." if node.get("list_style") == "numbered" else "•"
                lines.append(f"{prefix} {item}")
        elif node_type == "image":
            url = node.get("url") or ""
            lines.append(f"[image: {url}]")
        elif node_type == "graph":
            lines.append("[graph]")
        elif node_type == "object":
            object_type = node.get("object_type") or "object"
            object_id = node.get("object_id")
            lines.append(f"[{object_type} #{object_id}]")
    return "\n".join(lines)


def validate_document(body: str | None) -> None:
    doc = parse_document(body)
    for node in doc["nodes"]:
        _normalize_node(node)
