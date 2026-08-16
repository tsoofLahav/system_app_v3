"""Create an object embed and insert its pointer into the file document."""

from __future__ import annotations

from typing import Any

from models import (
    File,
    InformationPiece,
    ObjectEmbed,
    TaskList,
    db,
)
from areas.files.services.document_promote import promote_legacy_embeds
from areas.files.services.document_v3 import insert_embed_block, sync_object_anchors
from areas.objects.services.table_payload import (
    chart_enabled,
    empty_chart_table_payload,
    normalize_table_payload,
)

OBJECT_TYPES = frozenset({"task_list", "info", "image", "table"})
_LEGACY_CREATE_ALIASES = {"graph": "table"}


def normalize_create_type(type_: str) -> tuple[str, bool]:
    """Return (api_type, is_chart). ``graph`` → table + chart."""
    raw = (type_ or "").strip()
    if raw == "graph":
        return "table", True
    return raw, False


def create_embed_entity(type_: str, data: dict[str, Any]) -> ObjectEmbed:
    if type_ == "task_list":
        task_list = TaskList(title=data.get("title") or "")
        db.session.add(task_list)
        db.session.flush()
        return ObjectEmbed(
            file_id=data["file_id"],
            type="task_list",
            task_list_id=task_list.id,
        )
    if type_ == "info":
        entity = InformationPiece(
            title=data.get("title") or "",
            body=data.get("body") or "",
            metadata_=data.get("metadata") or {},
        )
        db.session.add(entity)
        db.session.flush()
        return ObjectEmbed(
            file_id=data["file_id"],
            type="info",
            information_id=entity.id,
        )
    payload = data.get("payload") or {}
    if type_ == "table":
        if data.get("_chart") or data.get("chart"):
            payload = normalize_table_payload(payload or empty_chart_table_payload())
        else:
            payload = normalize_table_payload(payload)
    return ObjectEmbed(
        file_id=data["file_id"],
        type=type_,
        payload=payload,
    )


def create_embed_in_file(
    file: File,
    *,
    type_: str,
    title: str = "",
    body: str = "",
    payload: dict[str, Any] | None = None,
    block_index: int | None = None,
    sort_key: int | None = None,
) -> ObjectEmbed:
    """Create embed row + pointer in ``file.document_json``. Caller commits."""
    api_type, is_chart = normalize_create_type(type_)
    if api_type not in OBJECT_TYPES:
        raise ValueError(f"type must be one of {sorted(OBJECT_TYPES | {'graph'})}")

    create_data: dict[str, Any] = {
        "file_id": file.id,
        "type": api_type,
        "title": title,
        "body": body,
    }
    if payload is not None:
        create_data["payload"] = payload
    if is_chart:
        create_data["_chart"] = True

    embed = create_embed_entity(api_type, create_data)
    db.session.add(embed)
    db.session.flush()

    pointer_type = api_type
    if api_type == "table" and (is_chart or chart_enabled(embed.payload)):
        pointer_type = "graph"

    file.document_json = insert_embed_block(
        file.document_json or "",
        embed.id,
        block_index=block_index,
        object_type=pointer_type,
    )
    embed.anchor = {"kind": "embed", "object_id": embed.id}
    embed.sort_key = sort_key if sort_key is not None else embed.id
    sync_object_anchors(file.document_json or "", [embed])
    promote_legacy_embeds(file)
    db.session.flush()
    return embed
