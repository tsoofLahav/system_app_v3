"""Object graph helpers: links keyed by objects.id, tags on objects."""

from __future__ import annotations

from models import EntityTag, File, InformationPiece, Link, ObjectEmbed, Tag, Topic, db


LINK_KINDS = {"related", "description"}
OBJECT_LINK_TYPES = {"task_list", "info", "image", "graph"}


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
    if embed.type == "graph":
        return "Graph"
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
    # Description links where this info is source and target is a file.
    desc = Link.query.filter_by(
        kind="description",
        source_type="info",
        source_id=object_id,
    ).all()
    for link in desc:
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
            }
        )
    node_ids = {n["object_id"] for n in nodes}

    edges = []
    seen = set()
    for link in Link.query.filter_by(workspace_id=workspace_id).all():
        kind = link.kind or "related"
        if kind == "description":
            # Description edges are info→file; diagram draws related info↔info only.
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
        elif (link.kind or "related") == "description" and link.source_id == embed.id:
            data["peer"] = {
                "type": "file",
                "id": link.target_id,
                "title": data.get("label") or "Text",
            }
            out.append(data)
            continue
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
