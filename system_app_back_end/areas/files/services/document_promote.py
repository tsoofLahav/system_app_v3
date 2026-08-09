"""Promote legacy inline embeds to object rows."""

from __future__ import annotations

from models import File, ObjectEmbed, db
from areas.files.services.document_marker_text import migrate_v3_json_to_editor_text
from areas.files.services.document_v3 import (
    apply_object_to_legacy_block,
    parse_document,
    pending_legacy_embeds,
    serialize_document,
)


def promote_legacy_embeds(file: File) -> bool:
    doc = parse_document(file.document_json)
    pending = pending_legacy_embeds(doc)
    if not pending:
        return False

    changed = False
    for block in pending:
        legacy = block.get("_legacy") or {}
        legacy_type = legacy.get("type")
        if legacy_type not in {"image", "graph"}:
            continue
        embed = ObjectEmbed(
            file_id=file.id,
            type=legacy_type,
            payload=dict(legacy),
        )
        db.session.add(embed)
        db.session.flush()
        doc = apply_object_to_legacy_block(doc, block["id"], embed.id)
        embed.anchor = {"kind": "embed", "object_id": embed.id}
        changed = True

    if changed:
        # Always persist v4 marker text, never raw v3 JSON.
        file.document_json = migrate_v3_json_to_editor_text(serialize_document(doc))
    return changed
