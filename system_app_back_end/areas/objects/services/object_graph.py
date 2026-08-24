"""Object graph helpers: links keyed by objects.id, tags on objects."""

from __future__ import annotations

from sqlalchemy import and_, or_

from models import EntityTag, File, InformationPiece, Link, ObjectEmbed, Tag, Topic, db


LINK_KINDS = {"related", "description"}
OBJECT_LINK_TYPES = {"task_list", "info", "image", "table"}


def related_requires_info(source_type: str, target_type: str) -> bool:
    """Related edges are info ↔ info only so the objects map stays info-only."""
    return source_type == "info" and target_type == "info"


def normalize_description_anchor(anchor) -> dict:
    """Object-local span: segment_id + start/end. file_id is optional listing glue."""
    if not isinstance(anchor, dict):
        raise ValueError("anchor required for description")
    segment_id = anchor.get("segment_id")
    if segment_id is None or str(segment_id).strip() == "":
        raise ValueError("anchor.segment_id required")
    try:
        start = int(anchor.get("start", 0))
        end = int(anchor.get("end", 0))
    except (TypeError, ValueError) as exc:
        raise ValueError("anchor start/end must be integers") from exc
    if end <= start:
        raise ValueError("anchor end must be greater than start")
    out = {
        "segment_id": str(segment_id),
        "start": start,
        "end": end,
    }
    if anchor.get("file_id") is not None:
        out["file_id"] = int(anchor["file_id"])
    if "block_id" in anchor and anchor["block_id"] is not None:
        out["block_id"] = anchor["block_id"]
    return out


def find_related_link(workspace_id: int, a_id: int, b_id: int) -> Link | None:
    return (
        Link.query.filter(
            Link.workspace_id == workspace_id,
            Link.kind == "related",
            Link.source_type == "info",
            Link.target_type == "info",
            or_(
                and_(Link.source_id == a_id, Link.target_id == b_id),
                and_(Link.source_id == b_id, Link.target_id == a_id),
            ),
        ).first()
    )


def ensure_related_info_link(
    workspace_id: int,
    source: ObjectEmbed,
    target: ObjectEmbed,
    label: str | None = None,
) -> Link:
    existing = find_related_link(workspace_id, source.id, target.id)
    if existing is not None:
        return existing
    link = Link(
        workspace_id=workspace_id,
        source_type="info",
        source_id=source.id,
        target_type="info",
        target_id=target.id,
        kind="related",
        label=label,
    )
    db.session.add(link)
    return link


def description_links_hosted_in_file(file_id: int) -> list[Link]:
    """Description rows whose source (host) object lives in this file."""
    host_ids = [
        row.id for row in ObjectEmbed.query.filter_by(file_id=file_id).all()
    ]
    if not host_ids:
        return []
    return (
        Link.query.filter(
            Link.kind == "description",
            Link.source_type.in_(tuple(OBJECT_LINK_TYPES)),
            Link.source_id.in_(host_ids),
            Link.target_type == "info",
        ).all()
    )


def info_peer_dict(embed: ObjectEmbed | None, object_id: int) -> dict:
    info = (
        db.session.get(InformationPiece, embed.information_id)
        if embed is not None and embed.information_id
        else None
    )
    return {
        "type": "info",
        "id": object_id,
        "title": (info.title if info else "") or "Info",
        "body": (info.body if info else "") or "",
        "file_id": embed.file_id if embed else None,
    }


def object_title(embed: ObjectEmbed) -> str:
    if embed.type == "info" and embed.information_id:
        info = db.session.get(InformationPiece, embed.information_id)
        if info is not None:
            return (info.title or "").strip() or "Info"
    if embed.type == "task_list" and embed.task_list_id:
        from models import TaskList

        tl = db.session.get(TaskList, embed.task_list_id)
        if tl is not None:
            return (tl.title or "").strip() or "Task list"
    if embed.type == "image":
        payload = embed.payload or {}
        return (payload.get("caption") or "").strip() or "Image"
    if embed.type == "table":
        from areas.objects.services.table_payload import chart_enabled

        return "Graph" if chart_enabled(embed.payload) else "Table"
    return embed.type


def tag_ids_for_object(object_id: int) -> list[int]:
    rows = EntityTag.query.filter_by(
        entity_type="object", entity_id=object_id
    ).all()
    return [r.tag_id for r in rows]


def tags_for_object(object_id: int) -> list[dict]:
    ids = tag_ids_for_object(object_id)
    if not ids:
        return []
    tags = Tag.query.filter(Tag.id.in_(ids)).order_by(Tag.name).all()
    return [t.to_dict() for t in tags]


def links_touching_object(object_id: int) -> list[Link]:
    """Undirected: object as source (object types) or target (object types)."""
    outbound = Link.query.filter(
        Link.source_type.in_(tuple(OBJECT_LINK_TYPES)),
        Link.source_id == object_id,
    ).all()
    inbound = Link.query.filter(
        Link.target_type.in_(tuple(OBJECT_LINK_TYPES)),
        Link.target_id == object_id,
    ).all()
    by_id = {link.id: link for link in outbound}
    for link in inbound:
        by_id[link.id] = link
    return list(by_id.values())


def delete_links_for_object(object_id: int, object_type: str) -> None:
    Link.query.filter(
        Link.source_type == object_type,
        Link.source_id == object_id,
    ).delete(synchronize_session=False)
    Link.query.filter(
        Link.target_type == object_type,
        Link.target_id == object_id,
    ).delete(synchronize_session=False)


def delete_links_for_file(file_id: int) -> None:
    Link.query.filter_by(target_type="file", target_id=file_id).delete(
        synchronize_session=False
    )


def workspace_object_ids(workspace_id: int) -> list[ObjectEmbed]:
    return (
        ObjectEmbed.query.join(File, File.id == ObjectEmbed.file_id)
        .join(Topic, Topic.id == File.topic_id)
        .filter(Topic.workspace_id == workspace_id)
        .order_by(ObjectEmbed.id)
        .all()
    )


def build_workspace_graph(workspace_id: int) -> dict:
    embeds = workspace_object_ids(workspace_id)
    embed_by_id = {e.id: e for e in embeds}
    nodes = []
    for embed in embeds:
        if embed.type != "info":
            continue
        file_row = db.session.get(File, embed.file_id)
        topic = db.session.get(Topic, file_row.topic_id) if file_row else None
        info = (
            db.session.get(InformationPiece, embed.information_id)
            if embed.information_id
            else None
        )
        nodes.append(
            {
                "object_id": embed.id,
                "type": embed.type,
                "title": object_title(embed),
                "body": (info.body or "") if info is not None else "",
                "information_id": embed.information_id,
                "file_id": embed.file_id,
                "topic_id": topic.id if topic is not None else None,
                "topic_color": topic.color if topic is not None else None,
                "tag_ids": tag_ids_for_object(embed.id),
                "diagram_x": embed.diagram_x,
                "diagram_y": embed.diagram_y,
            }
        )
    node_ids = {n["object_id"] for n in nodes}

    edges = []
    seen = set()
    for link in Link.query.filter_by(workspace_id=workspace_id).all():
        kind = link.kind or "related"
        if kind == "description":
            # Description is a span on a host object; the map draws related only.
            continue
        if link.source_type not in OBJECT_LINK_TYPES:
            continue
        if link.target_type not in OBJECT_LINK_TYPES:
            continue
        if link.source_id not in node_ids or link.target_id not in node_ids:
            continue
        key = (min(link.source_id, link.target_id), max(link.source_id, link.target_id), kind)
        if key in seen:
            continue
        seen.add(key)
        edges.append(
            {
                "id": link.id,
                "kind": kind,
                "source_id": link.source_id,
                "target_id": link.target_id,
                "label": link.label,
            }
        )
    return {"nodes": nodes, "edges": edges}


def apply_diagram_positions(workspace_id: int, rows: list) -> int:
    """Write map coordinates onto objects that belong to [workspace_id]."""
    embeds = {e.id: e for e in workspace_object_ids(workspace_id)}
    updated = 0
    for row in rows:
        if not isinstance(row, dict):
            continue
        raw_id = row.get("object_id")
        if raw_id is None:
            continue
        embed = embeds.get(int(raw_id))
        if embed is None:
            continue
        if row.get("x") is None or row.get("y") is None:
            continue
        embed.diagram_x = float(row["x"])
        embed.diagram_y = float(row["y"])
        updated += 1
    return updated


def connection_dicts_for_object(embed: ObjectEmbed) -> list[dict]:
    out = []
    for link in links_touching_object(embed.id):
        data = link.to_dict()
        other_id = None
        other_type = None
        if link.source_id == embed.id and link.source_type in OBJECT_LINK_TYPES:
            other_id = link.target_id
            other_type = link.target_type
        elif link.target_id == embed.id and link.target_type in OBJECT_LINK_TYPES:
            other_id = link.source_id
            other_type = link.source_type
        else:
            continue
        peer = db.session.get(ObjectEmbed, other_id) if other_type in OBJECT_LINK_TYPES else None
        data["peer"] = {
            "type": other_type,
            "id": other_id,
            "title": object_title(peer) if peer else f"{other_type} #{other_id}",
            "file_id": peer.file_id if peer else None,
        }
        out.append(data)
    return out
