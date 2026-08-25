"""Deep-copy a topic's live files and object content onto a new topic."""

from __future__ import annotations

import copy

from sqlalchemy import or_

from models import (
    EntityTag,
    File,
    InformationPiece,
    Link,
    ObjectEmbed,
    Task,
    TaskList,
    Topic,
    db,
)
from areas.files.services import file_ops
from areas.files.services.document_marker_text import (
    embed_ids_in_text,
    rewrite_pointer_ids,
)
from areas.files.services.document_v3 import sync_object_anchors
from areas.files.services.template_slots import stamp_template_slots
from areas.objects.services.object_graph import OBJECT_LINK_TYPES, tag_ids_for_object


def clone_topic_content(
    dest: Topic, source: Topic, *, copy_identity: bool = True
) -> None:
    """Fill ``dest`` with a full copy of ``source``'s live files and objects."""
    stamp_template_slots(source)
    dest.file_layout = source.file_layout or dest.file_layout
    if copy_identity:
        if not dest.icon:
            dest.icon = source.icon
        if not dest.color:
            dest.color = source.color
        _copy_topic_tags(dest, source)

    files = (
        File.query.filter_by(topic_id=source.id, archived_at=None)
        .order_by(File.order_index, File.id)
        .all()
    )
    id_map: dict[int, int] = {}
    file_id_map: dict[int, int] = {}
    for source_file in files:
        meta = dict(source_file.meta or {})
        new_file = file_ops.create_file(
            topic_id=dest.id,
            name=source_file.name,
            document_json=source_file.document_json or "",
            order_index=source_file.order_index,
            meta=meta,
        )
        file_id_map[source_file.id] = new_file.id
        body = source_file.document_json or ""
        for old_id in sorted(embed_ids_in_text(body)):
            src = db.session.get(ObjectEmbed, old_id)
            if src is None:
                continue
            clone = _clone_embed_to_file(src, new_file.id)
            id_map[old_id] = clone.id
            _copy_object_tags(old_id, clone.id)
        rewritten = rewrite_pointer_ids(body, id_map)
        new_file.document_json = rewritten
        embeds = ObjectEmbed.query.filter_by(file_id=new_file.id).all()
        sync_object_anchors(new_file.document_json or "", embeds)

    _clone_in_topic_links(source.workspace_id, id_map, file_id_map)
    db.session.flush()


def _copy_topic_tags(dest: Topic, source: Topic) -> None:
    existing = EntityTag.query.filter_by(
        entity_type="topic", entity_id=dest.id
    ).first()
    if existing is not None:
        return
    rows = EntityTag.query.filter_by(
        entity_type="topic", entity_id=source.id
    ).all()
    for row in rows:
        db.session.add(
            EntityTag(
                tag_id=row.tag_id,
                entity_type="topic",
                entity_id=dest.id,
            )
        )


def _copy_object_tags(old_object_id: int, new_object_id: int) -> None:
    for tag_id in tag_ids_for_object(old_object_id):
        db.session.add(
            EntityTag(
                tag_id=tag_id,
                entity_type="object",
                entity_id=new_object_id,
            )
        )


def _clone_embed_to_file(src: ObjectEmbed, dest_file_id: int) -> ObjectEmbed:
    task_list_id = None
    information_id = None
    if src.type == "task_list" and src.task_list_id:
        src_list = db.session.get(TaskList, src.task_list_id)
        title = src_list.title if src_list else ""
        new_list = TaskList(title=title or "")
        db.session.add(new_list)
        db.session.flush()
        task_list_id = new_list.id
        tasks = Task.query.filter_by(task_list_id=src.task_list_id).all()
        for t in tasks:
            db.session.add(
                Task(
                    task_list_id=new_list.id,
                    title=t.title,
                    status=t.status,
                    due_date=t.due_date,
                    list_order_index=t.list_order_index,
                    archived_at=t.archived_at,
                )
            )
    elif src.type == "info" and src.information_id:
        src_info = db.session.get(InformationPiece, src.information_id)
        info = InformationPiece(
            title=(src_info.title if src_info else "") or "",
            body=(src_info.body if src_info else "") or "",
            metadata_=copy.deepcopy(src_info.metadata_) if src_info else {},
        )
        db.session.add(info)
        db.session.flush()
        information_id = info.id

    clone = ObjectEmbed(
        file_id=dest_file_id,
        type=src.type,
        task_list_id=task_list_id,
        information_id=information_id,
        payload=copy.deepcopy(src.payload) if src.payload is not None else {},
        anchor={},
        sort_key=src.sort_key,
        diagram_x=src.diagram_x,
        diagram_y=src.diagram_y,
    )
    db.session.add(clone)
    db.session.flush()
    clone.anchor = {"kind": "embed", "object_id": clone.id}
    return clone


def _clone_in_topic_links(
    workspace_id: int,
    id_map: dict[int, int],
    file_id_map: dict[int, int],
) -> None:
    if not id_map:
        return
    old_ids = list(id_map.keys())
    links = (
        Link.query.filter(
            Link.workspace_id == workspace_id,
            or_(
                Link.source_id.in_(old_ids),
                Link.target_id.in_(old_ids),
            ),
        ).all()
    )
    seen: set[tuple] = set()
    for link in links:
        if link.source_type not in OBJECT_LINK_TYPES:
            continue
        if link.target_type not in OBJECT_LINK_TYPES:
            continue
        new_src = id_map.get(link.source_id)
        new_tgt = id_map.get(link.target_id)
        if new_src is None or new_tgt is None:
            continue
        key = (
            link.kind,
            link.source_type,
            new_src,
            link.target_type,
            new_tgt,
        )
        if key in seen:
            continue
        seen.add(key)
        anchor = copy.deepcopy(link.anchor) if link.anchor else None
        if isinstance(anchor, dict):
            old_fid = anchor.get("file_id")
            if old_fid in file_id_map:
                anchor["file_id"] = file_id_map[old_fid]
        db.session.add(
            Link(
                workspace_id=workspace_id,
                source_type=link.source_type,
                source_id=new_src,
                target_type=link.target_type,
                target_id=new_tgt,
                kind=link.kind or "related",
                anchor=anchor,
                label=link.label,
            )
        )
