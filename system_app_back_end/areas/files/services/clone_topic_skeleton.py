"""Copy a topic's file *structure* — names, layout, empty objects — not the prose."""

from __future__ import annotations

from models import File, ObjectEmbed, Topic, db
from areas.files.services.document_marker_text import (
    empty_editor_text,
    iter_embed_pointers,
)
from areas.files.services import file_ops
from areas.files.services.template_slots import stamp_template_slots
from areas.objects.services.create_embed import create_embed_in_file
from areas.objects.services.table_payload import (
    chart_enabled,
    empty_chart_table_payload,
    empty_table_payload,
)


def clone_topic_skeleton(dest: Topic, source: Topic) -> None:
    """Fill ``dest`` with empty shells of ``source``'s live files."""
    stamp_template_slots(source)
    dest.file_layout = source.file_layout or dest.file_layout
    files = (
        File.query.filter_by(topic_id=source.id, archived_at=None)
        .order_by(File.order_index, File.id)
        .all()
    )
    for source_file in files:
        meta = dict(source_file.meta or {})
        slot = meta.get("template_slot")
        new_file = file_ops.create_file(
            topic_id=dest.id,
            name=source_file.name,
            document_json=empty_editor_text(),
            order_index=source_file.order_index,
            meta={"template_slot": slot} if slot else {},
        )
        _clone_empty_embeds(source_file, new_file)
    db.session.flush()


def clone_slot_into_topic(
    dest: Topic, *, source: Topic, template_slot: str
) -> File | None:
    """Empty copy of one template file (matched by slot) into ``dest``."""
    stamp_template_slots(source)
    source_files = (
        File.query.filter(
            File.topic_id == source.id,
            File.archived_at.is_(None),
        )
        .order_by(File.order_index, File.id)
        .all()
    )
    match = next(
        (
            f
            for f in source_files
            if str((f.meta or {}).get("template_slot") or "") == template_slot
        ),
        None,
    )
    if match is None:
        return None
    new_file = file_ops.create_file(
        topic_id=dest.id,
        name=match.name,
        document_json=empty_editor_text(),
        order_index=match.order_index,
        meta={"template_slot": template_slot},
    )
    _clone_empty_embeds(match, new_file)
    db.session.flush()
    return new_file


def _clone_empty_embeds(source_file: File, dest_file: File) -> None:
    body = source_file.document_json or ""
    for _tag, object_id in iter_embed_pointers(body):
        embed = db.session.get(ObjectEmbed, object_id)
        if embed is None:
            continue
        kind, payload = _empty_kind(embed)
        create_embed_in_file(
            dest_file,
            type_=kind,
            title="",
            body="",
            payload=payload,
        )


def _empty_kind(embed: ObjectEmbed) -> tuple[str, dict | None]:
    if embed.type == "task_list":
        return "task_list", None
    if embed.type == "info":
        return "info", None
    if embed.type == "image":
        return "image", {}
    if embed.type == "table":
        if chart_enabled(embed.payload):
            return "graph", empty_chart_table_payload()
        rows = (embed.payload or {}).get("rows") or []
        cols = len(rows[0]) if rows and isinstance(rows[0], list) else 2
        return "table", empty_table_payload(columns=max(int(cols), 1))
    return embed.type, {}
