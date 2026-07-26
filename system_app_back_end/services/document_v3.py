"""JSON document codec — v3 ordered block tree with embed references."""

from __future__ import annotations

import json
import re
import uuid
from typing import Any

DOCUMENT_VERSION_V3 = 3
DOCUMENT_VERSION_V2 = 2
DOCUMENT_VERSION_V1 = 1
EMBED_CHAR = "\uFFFC"

INLINE_BLOCK_TYPES = {"paragraph", "heading", "list", "bullet_list", "ordered_list", "table"}
OBJECT_TYPES = {"task_list", "info", "image", "graph"}

_TASK_MARKER = re.compile(r"^\{\{task:(\d+)\}\}$")
_INFO_MARKER = re.compile(r"^\{\{info:(\d+)\}\}$")


def new_id(prefix: str = "b") -> str:
    return f"{prefix}{uuid.uuid4().hex[:8]}"


def empty_document() -> dict[str, Any]:
    return {"version": DOCUMENT_VERSION_V3, "blocks": []}


def empty_document_json() -> str:
    return serialize_document(empty_document())


def parse_document(body: str | None) -> dict[str, Any]:
    raw = body or ""
    if not raw.strip():
        return empty_document()
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return migrate_v1_nodes_to_v3(_migrate_plain_body_v1(raw)["nodes"])

    if not isinstance(data, dict):
        return migrate_v1_nodes_to_v3(_migrate_plain_body_v1(raw)["nodes"])

    version = int(data.get("version") or DOCUMENT_VERSION_V1)
    if version >= DOCUMENT_VERSION_V3 and isinstance(data.get("blocks"), list):
        return _normalize_v3(data)

    if version >= DOCUMENT_VERSION_V2 and "text" in data:
        return migrate_v2_to_v3(data)

    if isinstance(data.get("nodes"), list):
        return migrate_v1_nodes_to_v3(data["nodes"])

    return migrate_v1_nodes_to_v3(_migrate_plain_body_v1(raw)["nodes"])


def serialize_document(doc: dict[str, Any]) -> str:
    return json.dumps(_normalize_v3(doc), ensure_ascii=False, separators=(",", ":"))


def _normalize_v3(data: dict[str, Any]) -> dict[str, Any]:
    blocks_raw = data.get("blocks") if isinstance(data.get("blocks"), list) else []
    blocks: list[dict[str, Any]] = []
    for item in blocks_raw:
        if not isinstance(item, dict):
            continue
        block = _normalize_block(item)
        if block:
            blocks.append(block)
    return {"version": DOCUMENT_VERSION_V3, "blocks": blocks}


def _normalize_block(item: dict[str, Any]) -> dict[str, Any] | None:
    block_type = item.get("type")
    block_id = str(item.get("id") or new_id("b"))

    if block_type == "paragraph":
        return {
            "id": block_id,
            "type": "paragraph",
            "text": str(item.get("text") or ""),
            "spans": _normalize_spans(item.get("spans")),
        }
    if block_type == "heading":
        level = int(item.get("level") or 1)
        return {
            "id": block_id,
            "type": "heading",
            "level": max(1, min(level, 6)),
            "text": str(item.get("text") or ""),
            "spans": _normalize_spans(item.get("spans")),
        }
    if block_type in {"list", "bullet_list", "ordered_list"}:
        items = item.get("items") if isinstance(item.get("items"), list) else []
        if block_type == "ordered_list":
            list_style = "numbered"
        elif block_type == "bullet_list":
            list_style = "bullet"
        else:
            list_style = item.get("list_style") or "bullet"
            if list_style == "ordered":
                list_style = "numbered"
        normalized_type = "ordered_list" if list_style == "numbered" else "bullet_list"
        return {
            "id": block_id,
            "type": normalized_type,
            "items": [_normalize_list_item(i) for i in items if isinstance(i, dict)],
        }
    if block_type == "table":
        rows_raw = item.get("rows") if isinstance(item.get("rows"), list) else []
        rows: list[list[dict[str, Any]]] = []
        for row in rows_raw:
            if not isinstance(row, list):
                continue
            rows.append([_normalize_cell(c) for c in row])
        if not rows:
            rows = [[_empty_cell(), _empty_cell()]]
        return {"id": block_id, "type": "table", "rows": rows}
    if block_type == "embed":
        object_id = item.get("object_id")
        block: dict[str, Any] = {"id": block_id, "type": "embed"}
        if object_id is not None:
            block["object_id"] = int(object_id)
        legacy = item.get("_legacy")
        if isinstance(legacy, dict):
            block["_legacy"] = legacy
        return block
    return None


def _normalize_spans(raw: Any) -> list[dict[str, Any]]:
    if not isinstance(raw, list):
        return []
    spans: list[dict[str, Any]] = []
    for item in raw:
        if not isinstance(item, dict):
            continue
        start = int(item.get("start") or 0)
        end = int(item.get("end") or start)
        span: dict[str, Any] = {"start": start, "end": end}
        if item.get("bold"):
            span["bold"] = True
        if item.get("italic"):
            span["italic"] = True
        if item.get("underline"):
            span["underline"] = True
        if item.get("size") is not None:
            span["size"] = item["size"]
        if item.get("link"):
            span["link"] = str(item["link"])
        if item.get("color"):
            span["color"] = str(item["color"])
        spans.append(span)
    return spans


def _normalize_list_item(item: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": str(item.get("id") or new_id("li")),
        "text": str(item.get("text") or ""),
        "indent": max(0, int(item.get("indent") or 0)),
        "spans": _normalize_spans(item.get("spans")),
    }


def _empty_cell() -> dict[str, Any]:
    return {"text": "", "spans": []}


def _normalize_cell(cell: Any) -> dict[str, Any]:
    if isinstance(cell, dict):
        return {
            "text": str(cell.get("text") or ""),
            "spans": _normalize_spans(cell.get("spans")),
        }
    return {"text": str(cell or ""), "spans": []}


def _shift_spans(spans: list[dict], offset: int, length: int) -> list[dict]:
    result: list[dict] = []
    for span in spans:
        start = int(span.get("start") or 0) - offset
        end = int(span.get("end") or 0) - offset
        if end <= 0 or start >= length:
            continue
        result.append(
            {
                **{k: v for k, v in span.items() if k not in {"start", "end"}},
                "start": max(0, start),
                "end": min(length, end),
            }
        )
    return result


def migrate_v1_nodes_to_v3(nodes: list[dict[str, Any]]) -> dict[str, Any]:
    blocks: list[dict[str, Any]] = []
    for node in nodes:
        node_type = node.get("type")
        if node_type == "paragraph":
            blocks.append(
                {
                    "id": str(node.get("id") or new_id("b")),
                    "type": "paragraph",
                    "text": str(node.get("text") or ""),
                    "spans": _normalize_spans(node.get("spans")),
                }
            )
        elif node_type == "heading":
            blocks.append(
                {
                    "id": str(node.get("id") or new_id("b")),
                    "type": "heading",
                    "level": int(node.get("level") or 1),
                    "text": str(node.get("text") or ""),
                    "spans": _normalize_spans(node.get("spans")),
                }
            )
        elif node_type == "list":
            items_raw = node.get("items") or []
            items = []
            for i, item in enumerate(items_raw):
                if isinstance(item, dict):
                    items.append(_normalize_list_item(item))
                else:
                    items.append(
                        {
                            "id": new_id("li"),
                            "text": str(item),
                            "indent": 0,
                            "spans": [],
                        }
                    )
            blocks.append(
                {
                    "id": str(node.get("id") or new_id("b")),
                    "type": "ordered_list"
                    if (node.get("list_style") or "bullet") in {"numbered", "ordered"}
                    else "bullet_list",
                    "items": items,
                }
            )
        elif node_type == "table":
            rows_raw = node.get("rows") or [["", ""]]
            rows = [[_normalize_cell(c) for c in row] for row in rows_raw if isinstance(row, list)]
            blocks.append(
                {
                    "id": str(node.get("id") or new_id("b")),
                    "type": "table",
                    "rows": rows or [[_empty_cell(), _empty_cell()]],
                }
            )
        elif node_type == "image":
            blocks.append(
                {
                    "id": str(node.get("id") or new_id("b")),
                    "type": "embed",
                    "object_id": None,
                    "_legacy": {
                        "type": "image",
                        "url": str(node.get("url") or ""),
                        **({"width": node["width"]} if node.get("width") is not None else {}),
                    },
                }
            )
        elif node_type == "graph":
            blocks.append(
                {
                    "id": str(node.get("id") or new_id("b")),
                    "type": "embed",
                    "object_id": None,
                    "_legacy": {
                        "type": "graph",
                        "labels": node.get("labels") or [],
                        "values": node.get("values") or [],
                    },
                }
            )
        elif node_type == "object":
            blocks.append(
                {
                    "id": str(node.get("id") or new_id("b")),
                    "type": "embed",
                    "object_id": int(node["object_id"]),
                }
            )
    return _normalize_v3({"version": DOCUMENT_VERSION_V3, "blocks": blocks})


def migrate_v2_to_v3(data: dict[str, Any]) -> dict[str, Any]:
    v2 = _normalize_v2_for_migration(data)
    text = v2["text"]
    spans = v2["spans"]
    regions = v2["regions"]
    embeds = sorted(v2["embeds"], key=lambda e: int(e["offset"]))

    blocks: list[dict[str, Any]] = []
    pos = 0
    for embed in embeds:
        offset = int(embed["offset"])
        if offset > pos:
            blocks.extend(_segment_to_blocks(text[pos:offset], regions, spans, pos))
        if embed.get("kind") == "object":
            blocks.append(
                {
                    "id": str(embed.get("id") or new_id("b")),
                    "type": "embed",
                    "object_id": int(embed["object_id"]),
                }
            )
        elif embed.get("kind") == "image":
            legacy: dict[str, Any] = {
                "type": "image",
                "url": str(embed.get("url") or ""),
            }
            if embed.get("width") is not None:
                legacy["width"] = embed["width"]
            blocks.append(
                {
                    "id": str(embed.get("id") or new_id("b")),
                    "type": "embed",
                    "object_id": None,
                    "_legacy": legacy,
                }
            )
        elif embed.get("kind") == "graph":
            blocks.append(
                {
                    "id": str(embed.get("id") or new_id("b")),
                    "type": "embed",
                    "object_id": None,
                    "_legacy": {
                        "type": "graph",
                        "labels": embed.get("labels") or [],
                        "values": embed.get("values") or [],
                    },
                }
            )
        pos = offset + 1

    if pos < len(text):
        blocks.extend(_segment_to_blocks(text[pos:], regions, spans, pos))

    if not blocks:
        blocks.append({"id": new_id("b"), "type": "paragraph", "text": "", "spans": []})

    return _normalize_v3({"version": DOCUMENT_VERSION_V3, "blocks": blocks})


def _segment_to_blocks(
    segment: str,
    regions: list[dict],
    spans: list[dict],
    base_offset: int,
) -> list[dict[str, Any]]:
    if not segment:
        return []
    end = base_offset + len(segment)
    region = _region_at(regions, base_offset, end)
    if region and region.get("kind") == "list":
        return [_list_block_from_segment(region, segment, spans, base_offset)]
    if region and region.get("kind") == "table":
        return [_table_block_from_segment(region, segment, spans, base_offset)]
    blocks: list[dict[str, Any]] = []
    for part in segment.split("\n\n"):
        if not part and blocks:
            continue
        blocks.append(
            {
                "id": new_id("b"),
                "type": "paragraph",
                "text": part,
                "spans": _shift_spans(spans, base_offset, len(part)),
            }
        )
        base_offset += len(part) + 2
    return blocks or [
        {"id": new_id("b"), "type": "paragraph", "text": segment, "spans": _shift_spans(spans, base_offset, len(segment))}
    ]


def _normalize_v2_for_migration(data: dict[str, Any]) -> dict[str, Any]:
    text = str(data.get("text") or "")
    spans = data.get("spans") if isinstance(data.get("spans"), list) else []
    regions_raw = data.get("regions") if isinstance(data.get("regions"), list) else []
    embeds_raw = data.get("embeds") if isinstance(data.get("embeds"), list) else []

    regions: list[dict[str, Any]] = []
    for item in regions_raw:
        if not isinstance(item, dict) or item.get("kind") not in {"list", "table"}:
            continue
        start = int(item.get("start") or 0)
        end = int(item.get("end") or start)
        region = {
            "id": str(item.get("id") or new_id("r")),
            "kind": item.get("kind"),
            "start": start,
            "end": max(start, end),
        }
        if region["kind"] == "list":
            region["list_style"] = item.get("list_style") or "bullet"
        else:
            region["rows"] = item.get("rows") if isinstance(item.get("rows"), list) else [["", ""]]
        regions.append(region)

    embeds: list[dict[str, Any]] = []
    for item in embeds_raw:
        if not isinstance(item, dict):
            continue
        embed = _normalize_v2_embed(item)
        if embed:
            embeds.append(embed)

    text, embeds = _ensure_embed_chars(text, embeds)
    return {"text": text, "spans": spans, "regions": regions, "embeds": embeds}


def _normalize_v2_embed(item: dict[str, Any]) -> dict[str, Any] | None:
    kind = item.get("kind")
    if kind == "object":
        object_type = item.get("object_type")
        if object_type not in {"task_list", "info"}:
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
        return {
            "id": str(item.get("id") or new_id("e")),
            "kind": "graph",
            "offset": int(item.get("offset") or 0),
            "labels": item.get("labels") if isinstance(item.get("labels"), list) else [],
            "values": item.get("values") if isinstance(item.get("values"), list) else [],
        }
    return None


def _ensure_embed_chars(text: str, embeds: list[dict[str, Any]]) -> tuple[str, list[dict]]:
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


def _region_at(regions: list[dict], start: int, end: int) -> dict | None:
    for region in regions:
        if int(region["start"]) <= start and int(region["end"]) >= end:
            return region
    return None


def _split_paragraphs(segment: str) -> list[str]:
    if "\n\n" not in segment:
        return [segment]
    parts = segment.split("\n\n")
    result: list[str] = []
    for i, part in enumerate(parts):
        if i > 0:
            result.append("\n\n")
        if part:
            result.append(part)
    merged: list[str] = []
    buf = ""
    for part in result:
        if part == "\n\n":
            if buf:
                merged.append(buf)
                buf = ""
            merged.append("\n\n")
        else:
            buf += part
    if buf:
        merged.append(buf)
    return [p for p in merged if p != "\n\n"] or [segment]


def _list_block_from_segment(
    region: dict, segment: str, spans: list[dict], base_offset: int
) -> dict[str, Any]:
    list_style = region.get("list_style") or "bullet"
    if list_style == "ordered":
        list_style = "numbered"
    normalized_type = "ordered_list" if list_style == "numbered" else "bullet_list"
    items: list[dict[str, Any]] = []
    for line in segment.splitlines():
        stripped = line.lstrip("\t")
        indent = max(0, (len(line) - len(stripped)) // 2)
        text = stripped
        if list_style == "numbered":
            text = re.sub(r"^\d+\.\s*", "", text)
        else:
            text = re.sub(r"^[•\-*]\s*", "", text)
        items.append(
            {
                "id": new_id("li"),
                "text": text,
                "indent": indent,
                "spans": _shift_spans(spans, base_offset + len(line) - len(text), len(text)),
            }
        )
    if not items:
        items = [{"id": new_id("li"), "text": "", "indent": 0, "spans": []}]
    return {
        "id": str(region.get("id") or new_id("b")),
        "type": normalized_type,
        "items": items,
    }


def _table_block_from_segment(
    region: dict, segment: str, spans: list[dict], base_offset: int
) -> dict[str, Any]:
    rows_raw = region.get("rows")
    if isinstance(rows_raw, list) and rows_raw:
        rows = [[_normalize_cell(c) for c in row] for row in rows_raw if isinstance(row, list)]
    else:
        rows = []
        for line in segment.splitlines():
            cells = line.split("\t")
            rows.append([{"text": c, "spans": []} for c in cells])
    if not rows:
        rows = [[_empty_cell(), _empty_cell()]]
    return {"id": str(region.get("id") or new_id("b")), "type": "table", "rows": rows}


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


def insert_embed_block(
    body: str,
    object_id: int,
    *,
    block_index: int | None = None,
    block_id: str | None = None,
) -> str:
    doc = parse_document(body)
    blocks = doc["blocks"]
    index = len(blocks) if block_index is None else max(0, min(int(block_index), len(blocks)))
    block = {
        "id": block_id or new_id("b"),
        "type": "embed",
        "object_id": int(object_id),
    }
    blocks.insert(index, block)
    return serialize_document(doc)


def move_embed_block(body: str, block_id: str, new_index: int) -> str:
    doc = parse_document(body)
    blocks = doc["blocks"]
    current = next((i for i, b in enumerate(blocks) if b.get("id") == block_id), None)
    if current is None:
        return serialize_document(doc)
    block = blocks.pop(current)
    index = max(0, min(int(new_index), len(blocks)))
    blocks.insert(index, block)
    return serialize_document(doc)


def remove_embed_block(body: str, block_id: str) -> str:
    doc = parse_document(body)
    doc["blocks"] = [b for b in doc["blocks"] if b.get("id") != block_id]
    return serialize_document(doc)


def remove_object_embeds(body: str, object_id: int) -> str:
    doc = parse_document(body)
    doc["blocks"] = [
        b
        for b in doc["blocks"]
        if not (b.get("type") == "embed" and int(b.get("object_id") or -1) == int(object_id))
    ]
    return serialize_document(doc)


def sync_object_anchors(body: str, objects: list) -> None:
    doc = parse_document(body)
    by_object: dict[int, dict] = {}
    for block in doc["blocks"]:
        if block.get("type") != "embed":
            continue
        object_id = block.get("object_id")
        if object_id is not None:
            by_object[int(object_id)] = {"kind": "embed", "block_id": block["id"]}
    for obj in objects:
        hit = by_object.get(obj.id)
        if hit:
            obj.anchor = hit


def validate_document(body: str | None, known_object_ids: set[int] | None = None) -> None:
    doc = parse_document(body)
    if known_object_ids is None:
        return
    for block in doc["blocks"]:
        if block.get("type") != "embed":
            continue
        object_id = block.get("object_id")
        if object_id is not None and int(object_id) not in known_object_ids:
            raise ValueError(f"unknown object_id in document: {object_id}")


def find_embed_block_index(doc: dict[str, Any], object_id: int) -> int | None:
    for i, block in enumerate(doc["blocks"]):
        if block.get("type") == "embed" and int(block.get("object_id") or -1) == int(object_id):
            return i
    return None


def pending_legacy_embeds(doc: dict[str, Any]) -> list[dict[str, Any]]:
    pending: list[dict[str, Any]] = []
    for block in doc["blocks"]:
        if block.get("type") == "embed" and block.get("object_id") is None:
            legacy = block.get("_legacy")
            if isinstance(legacy, dict):
                pending.append(block)
    return pending


def apply_object_to_legacy_block(
    doc: dict[str, Any], block_id: str, object_id: int
) -> dict[str, Any]:
    blocks = []
    for block in doc["blocks"]:
        if block.get("id") == block_id:
            blocks.append(
                {"id": block_id, "type": "embed", "object_id": int(object_id)}
            )
        else:
            blocks.append(block)
    return _normalize_v3({"version": DOCUMENT_VERSION_V3, "blocks": blocks})


# Legacy aliases
def insert_embed(body: str, embed: dict[str, Any], *, offset: int | None = None) -> str:
    object_id = embed.get("object_id")
    if object_id is None:
        raise ValueError("embed requires object_id in v3")
    return insert_embed_block(body, int(object_id), block_index=offset)


def move_embed(body: str, embed_id: str, new_offset: int) -> str:
    return move_embed_block(body, embed_id, new_offset)


def remove_object_nodes(body: str, object_id: int) -> str:
    return remove_object_embeds(body, object_id)


def object_node_for(object_id: int, object_type: str, *, node_id: str | None = None) -> dict:
    return {"id": node_id or new_id("b"), "type": "embed", "object_id": object_id}


def insert_region(body: str, region: dict[str, Any], *, offset: int | None = None) -> str:
    doc = parse_document(body)
    blocks = doc["blocks"]
    index = len(blocks) if offset is None else max(0, min(int(offset), len(blocks)))
    kind = region.get("kind")
    if kind == "list":
        list_style = region.get("list_style") or "bullet"
        if list_style == "ordered":
            list_style = "numbered"
        block_type = "ordered_list" if list_style == "numbered" else "bullet_list"
        block = {
            "id": str(region.get("id") or new_id("b")),
            "type": block_type,
            "items": [{"id": new_id("li"), "text": "", "indent": 0, "spans": []}],
        }
    elif kind == "table":
        block = {
            "id": str(region.get("id") or new_id("b")),
            "type": "table",
            "rows": region.get("rows") or [[_empty_cell(), _empty_cell()]],
        }
    else:
        raise ValueError("invalid region kind")
    blocks.insert(index, block)
    return serialize_document(doc)


def insert_node(body: str, node: dict[str, Any], *, index: int | None = None) -> str:
    doc = parse_document(body)
    migrated = migrate_v1_nodes_to_v3([node])
    new_blocks = migrated["blocks"]
    if not new_blocks:
        return serialize_document(doc)
    idx = len(doc["blocks"]) if index is None else max(0, min(int(index), len(doc["blocks"])))
    for offset, block in enumerate(new_blocks):
        doc["blocks"].insert(idx + offset, block)
    return serialize_document(doc)


def document_plain_text(body: str | None) -> str:
    from services.document_agent_text import document_to_agent_text

    return document_to_agent_text(body)
