"""JSON document body codec — v2 inline text + regions + embeds."""

from __future__ import annotations

import json
import re
import uuid
from typing import Any

DOCUMENT_VERSION_V2 = 2
DOCUMENT_VERSION_V1 = 1
EMBED_CHAR = "\uFFFC"

REGION_KINDS = {"list", "table"}
EMBED_KINDS = {"image", "graph", "object"}
OBJECT_TYPES = {"task_list", "info"}

_TASK_MARKER = re.compile(r"^\{\{task:(\d+)\}\}$")
_INFO_MARKER = re.compile(r"^\{\{info:(\d+)\}\}$")


def new_id(prefix: str = "e") -> str:
    return f"{prefix}{uuid.uuid4().hex[:8]}"


def empty_document() -> dict[str, Any]:
    return {
        "version": DOCUMENT_VERSION_V2,
        "text": "",
        "spans": [],
        "regions": [],
        "embeds": [],
    }


def empty_document_json() -> str:
    return serialize_document(empty_document())


def parse_document(body: str | None) -> dict[str, Any]:
    raw = body or ""
    if not raw.strip():
        return empty_document()
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return migrate_v1_nodes_to_v2(_migrate_plain_body_v1(raw)["nodes"])

    if not isinstance(data, dict):
        return migrate_v1_nodes_to_v2(_migrate_plain_body_v1(raw)["nodes"])

    version = int(data.get("version") or DOCUMENT_VERSION_V1)
    if version >= DOCUMENT_VERSION_V2 and "text" in data:
        return _normalize_v2(data)

    if "nodes" in data and isinstance(data.get("nodes"), list):
        return migrate_v1_nodes_to_v2(data["nodes"])

    return migrate_v1_nodes_to_v2(_migrate_plain_body_v1(raw)["nodes"])


def serialize_document(doc: dict[str, Any]) -> str:
    normalized = _normalize_v2(doc)
    return json.dumps(normalized, ensure_ascii=False, separators=(",", ":"))


def _normalize_v2(data: dict[str, Any]) -> dict[str, Any]:
    text = str(data.get("text") or "")
    spans = data.get("spans") if isinstance(data.get("spans"), list) else []
    regions_raw = data.get("regions") if isinstance(data.get("regions"), list) else []
    embeds_raw = data.get("embeds") if isinstance(data.get("embeds"), list) else []

    regions: list[dict[str, Any]] = []
    for item in regions_raw:
        if not isinstance(item, dict):
            continue
        kind = item.get("kind")
        if kind not in REGION_KINDS:
            continue
        start = int(item.get("start") or 0)
        end = int(item.get("end") or start)
        region = {
            "id": str(item.get("id") or new_id("r")),
            "kind": kind,
            "start": max(0, start),
            "end": max(start, end),
        }
        if kind == "list":
            region["list_style"] = item.get("list_style") or "bullet"
        elif kind == "table":
            rows = item.get("rows")
            region["rows"] = rows if isinstance(rows, list) else [["", ""]]
        regions.append(region)

    embeds: list[dict[str, Any]] = []
    for item in embeds_raw:
        if not isinstance(item, dict):
            continue
        embed = _normalize_embed(item)
        if embed:
            embeds.append(embed)

    text, embeds = _ensure_embed_chars(text, embeds)
    return {
        "version": DOCUMENT_VERSION_V2,
        "text": text,
        "spans": spans,
        "regions": regions,
        "embeds": sorted(embeds, key=lambda e: e["offset"]),
    }


def _normalize_embed(item: dict[str, Any]) -> dict[str, Any] | None:
    kind = item.get("kind")
    if kind == "object":
        object_type = item.get("object_type")
        if object_type not in OBJECT_TYPES:
            return None
        return {
            "id": str(item.get("id") or new_id("e")),
            "kind": "object",
            "object_type": object_type,
            "object_id": int(item["object_id"]),
            "offset": int(item.get("offset") or 0),
        }
    if kind == "image":
        data = {
            "id": str(item.get("id") or new_id("e")),
            "kind": "image",
            "offset": int(item.get("offset") or 0),
            "url": str(item.get("url") or ""),
        }
        if item.get("width") is not None:
            data["width"] = item["width"]
        return data
    if kind == "graph":
        labels = item.get("labels")
        values = item.get("values")
        return {
            "id": str(item.get("id") or new_id("e")),
            "kind": "graph",
            "offset": int(item.get("offset") or 0),
            "labels": labels if isinstance(labels, list) else [],
            "values": values if isinstance(values, list) else [],
        }
    return None


def _ensure_embed_chars(text: str, embeds: list[dict[str, Any]]) -> tuple[str, list[dict]]:
    """On load: insert missing EMBED_CHAR at each embed offset."""
    if not embeds:
        return text.replace(EMBED_CHAR, ""), []
    embeds = sorted([dict(e) for e in embeds], key=lambda e: int(e["offset"]))
    chars = list(text)
    adjust = 0
    result: list[dict] = []
    for embed in embeds:
        pos = max(0, min(int(embed["offset"]) + adjust, len(chars)))
        if pos >= len(chars) or chars[pos] != EMBED_CHAR:
            chars.insert(pos, EMBED_CHAR)
            adjust += 1
        updated = dict(embed)
        updated["offset"] = pos
        result.append(updated)
    return "".join(chars), result


def migrate_v1_nodes_to_v2(nodes: list[dict[str, Any]]) -> dict[str, Any]:
    text_parts: list[str] = []
    spans: list[dict] = []
    regions: list[dict] = []
    embeds: list[dict] = []
    cursor = 0

    def append_text(s: str) -> int:
        nonlocal cursor
        start = cursor
        text_parts.append(s)
        cursor += len(s)
        return start

    for node in nodes:
        node_type = node.get("type")
        if node_type == "paragraph":
            block = str(node.get("text") or "")
            if text_parts and not text_parts[-1].endswith("\n"):
                append_text("\n")
            start = cursor
            append_text(block)
            for span in node.get("spans") or []:
                if isinstance(span, dict):
                    spans.append(
                        {
                            **span,
                            "start": int(span.get("start", 0)) + start,
                            "end": int(span.get("end", 0)) + start,
                        }
                    )
        elif node_type == "list":
            if text_parts:
                append_text("\n")
            items = node.get("items") or [""]
            list_style = node.get("list_style") or "bullet"
            lines = []
            for i, item in enumerate(items):
                prefix = f"{i + 1}. " if list_style == "numbered" else "• "
                lines.append(f"{prefix}{item}")
            block = "\n".join(lines)
            start = cursor
            append_text(block)
            regions.append(
                {
                    "id": new_id("r"),
                    "kind": "list",
                    "start": start,
                    "end": cursor,
                    "list_style": list_style,
                }
            )
        elif node_type == "table":
            if text_parts:
                append_text("\n")
            rows = node.get("rows") or [["", ""]]
            lines = ["\t".join(str(c) for c in row) for row in rows if isinstance(row, list)]
            block = "\n".join(lines)
            start = cursor
            append_text(block)
            regions.append(
                {
                    "id": new_id("r"),
                    "kind": "table",
                    "start": start,
                    "end": cursor,
                    "rows": rows,
                }
            )
        elif node_type == "image":
            if text_parts:
                append_text("\n")
            embed: dict[str, Any] = {
                "id": new_id("e"),
                "kind": "image",
                "offset": cursor,
                "url": str(node.get("url") or ""),
            }
            if node.get("width") is not None:
                embed["width"] = node["width"]
            embeds.append(embed)
            append_text(EMBED_CHAR)
        elif node_type == "graph":
            if text_parts:
                append_text("\n")
            embeds.append(
                {
                    "id": new_id("e"),
                    "kind": "graph",
                    "offset": cursor,
                    "labels": node.get("labels") or [],
                    "values": node.get("values") or [],
                }
            )
            append_text(EMBED_CHAR)
        elif node_type == "object":
            if text_parts:
                append_text("\n")
            embeds.append(
                {
                    "id": new_id("e"),
                    "kind": "object",
                    "object_type": node.get("object_type"),
                    "object_id": int(node["object_id"]),
                    "offset": cursor,
                }
            )
            append_text(EMBED_CHAR)

    text = "".join(text_parts)
    return _normalize_v2(
        {"version": DOCUMENT_VERSION_V2, "text": text, "spans": spans, "regions": regions, "embeds": embeds}
    )


def _migrate_plain_body_v1(body: str) -> dict[str, Any]:
    nodes: list[dict[str, Any]] = []
    for line in body.splitlines():
        stripped = line.strip()
        task_match = _TASK_MARKER.match(stripped)
        if task_match:
            nodes.append(
                {
                    "id": new_id("n"),
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
                    "id": new_id("n"),
                    "type": "object",
                    "object_type": "info",
                    "object_id": int(info_match.group(1)),
                }
            )
            continue
        if line or nodes:
            nodes.append({"id": new_id("n"), "type": "paragraph", "text": line, "spans": []})
    if not nodes:
        nodes.append({"id": new_id("n"), "type": "paragraph", "text": "", "spans": []})
    return {"version": DOCUMENT_VERSION_V1, "nodes": nodes}


def insert_embed(
    body: str,
    embed: dict[str, Any],
    *,
    offset: int | None = None,
) -> str:
    doc = parse_document(body)
    pos = len(doc["text"]) if offset is None else max(0, min(int(offset), len(doc["text"])))
    normalized = _normalize_embed({**embed, "offset": pos})
    if not normalized:
        raise ValueError("invalid embed")
    chars = list(doc["text"])
    chars.insert(pos, EMBED_CHAR)
    doc["text"] = "".join(chars)
    for e in doc["embeds"]:
        if int(e["offset"]) >= pos:
            e["offset"] = int(e["offset"]) + 1
    normalized["offset"] = pos
    doc["embeds"].append(normalized)
    return serialize_document(doc)


def insert_region(
    body: str,
    region: dict[str, Any],
    *,
    offset: int | None = None,
) -> str:
    doc = parse_document(body)
    kind = region.get("kind")
    if kind not in REGION_KINDS:
        raise ValueError("invalid region kind")
    text = doc["text"]
    pos = len(text) if offset is None else max(0, min(offset, len(text)))

    if kind == "list":
        list_style = region.get("list_style") or "bullet"
        seed = "• \n" if list_style == "bullet" else "1. \n"
    else:
        seed = "\t\n\t"

    chars = list(text)
    chars[pos:pos] = list(seed)
    start = pos
    end = pos + len(seed)
    doc["text"] = "".join(chars)
    _shift_at_offset(doc, pos, len(seed))
    entry: dict[str, Any] = {
        "id": str(region.get("id") or new_id("r")),
        "kind": kind,
        "start": start,
        "end": end,
    }
    if kind == "list":
        entry["list_style"] = region.get("list_style") or "bullet"
    else:
        entry["rows"] = region.get("rows") or [["", ""]]
    doc["regions"].append(entry)
    return serialize_document(doc)


def remove_object_embeds(body: str, object_id: int) -> str:
    doc = parse_document(body)
    to_remove = [
        e
        for e in doc["embeds"]
        if e.get("kind") == "object" and int(e.get("object_id") or 0) == object_id
    ]
    for embed in to_remove:
        doc = _remove_embed_by_id(doc, embed["id"])
    return serialize_document(doc)


def _remove_embed_by_id(doc: dict[str, Any], embed_id: str) -> dict[str, Any]:
    embed = next((e for e in doc["embeds"] if e["id"] == embed_id), None)
    if embed is None:
        return doc
    offset = int(embed["offset"])
    chars = list(doc["text"])
    if 0 <= offset < len(chars) and chars[offset] == EMBED_CHAR:
        chars.pop(offset)
    doc["text"] = "".join(chars)
    doc["embeds"] = [e for e in doc["embeds"] if e["id"] != embed_id]
    _shift_at_offset(doc, offset, -1)
    return doc


def move_embed(body: str, embed_id: str, new_offset: int) -> str:
    doc = parse_document(body)
    embed = next((e for e in doc["embeds"] if e["id"] == embed_id), None)
    if embed is None:
        return serialize_document(doc)
    doc = _remove_embed_by_id(doc, embed_id)
    embed["offset"] = max(0, min(new_offset, len(doc["text"])))
    doc["embeds"].append(embed)
    chars = list(doc["text"])
    pos = int(embed["offset"])
    chars.insert(pos, EMBED_CHAR)
    doc["text"] = "".join(chars)
    for e in doc["embeds"]:
        if e["id"] != embed_id and e["offset"] >= pos:
            e["offset"] += 1
    embed["offset"] = pos
    return serialize_document(doc)


def _shift_at_offset(doc: dict[str, Any], offset: int, delta: int) -> None:
    for e in doc["embeds"]:
        if e["offset"] >= offset:
            e["offset"] += delta
    for r in doc["regions"]:
        if r["start"] >= offset:
            r["start"] += delta
        if r["end"] >= offset:
            r["end"] += delta
    for s in doc["spans"]:
        if s.get("start", 0) >= offset:
            s["start"] = int(s["start"]) + delta
        if s.get("end", 0) >= offset:
            s["end"] = int(s["end"]) + delta


def sync_object_anchors(body: str, objects: list) -> None:
    doc = parse_document(body)
    by_object: dict[int, dict] = {}
    for embed in doc["embeds"]:
        if embed.get("kind") != "object":
            continue
        object_id = embed.get("object_id")
        if object_id is not None:
            by_object[int(object_id)] = {
                "kind": "embed",
                "embed_id": embed["id"],
                "offset": embed["offset"],
            }
    for obj in objects:
        hit = by_object.get(obj.id)
        if hit:
            obj.anchor = hit


def document_plain_text(body: str | None) -> str:
    doc = parse_document(body)
    lines: list[str] = []
    text = doc["text"].replace(EMBED_CHAR, " ")
    if text:
        lines.append(text)
    for embed in doc["embeds"]:
        kind = embed.get("kind")
        if kind == "object":
            lines.append(f"[{embed.get('object_type')} #{embed.get('object_id')}]")
        elif kind == "image":
            lines.append(f"[image: {embed.get('url')}]")
        elif kind == "graph":
            lines.append("[graph]")
    return "\n".join(lines)


def validate_document(body: str | None) -> None:
    parse_document(body)


# Legacy aliases for older callers
def insert_node(body: str, node: dict[str, Any], *, index: int | None = None) -> str:
    doc_v1 = {"version": 1, "nodes": parse_document(body).get("nodes", [])}
    if "nodes" not in doc_v1 or not doc_v1["nodes"]:
        # re-parse as v1 if needed — migrate back not supported; append via v2
        pass
    migrated = migrate_v1_nodes_to_v2([node])
    current = parse_document(body)
    current["text"] += migrated["text"]
    current["regions"].extend(migrated["regions"])
    current["embeds"].extend(migrated["embeds"])
    return serialize_document(current)


def remove_object_nodes(body: str, object_id: int) -> str:
    return remove_object_embeds(body, object_id)


def object_node_for(object_id: int, object_type: str, *, node_id: str | None = None) -> dict:
    return {
        "id": node_id or new_id("e"),
        "kind": "object",
        "object_type": object_type,
        "object_id": object_id,
        "offset": 0,
    }
