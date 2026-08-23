from flask import Blueprint, jsonify, request

from models import (
    EntityTag,
    File,
    InformationPiece,
    Link,
    ObjectEmbed,
    TaskList,
    Topic,
    db,
)
from shared.helpers import get_or_404
from shared.bootstrap import default_workspace_id
from areas.objects.services.create_embed import (
    OBJECT_TYPES,
    create_embed_in_file,
    normalize_create_type,
)
from areas.objects.services.delete_cascade import delete_object_embed_cascade
from areas.objects.services.task_list_order import tasks_for_list
from areas.objects.services.object_graph import (
    LINK_KINDS,
    OBJECT_LINK_TYPES,
    apply_diagram_positions,
    build_workspace_graph,
    connection_dicts_for_object,
    tags_for_object,
)

objects_bp = Blueprint("objects", __name__)

_OBJECT_TYPES = OBJECT_TYPES


def _workspace_for_object(embed: ObjectEmbed) -> int | None:
    file = db.session.get(File, embed.file_id)
    if file is None:
        return None
    topic = db.session.get(Topic, file.topic_id)
    return topic.workspace_id if topic else None


def _resolve_embed(obj: ObjectEmbed) -> dict:
    task_list = (
        db.session.get(TaskList, obj.task_list_id) if obj.task_list_id else None
    )
    tasks = tasks_for_list(obj.task_list_id) if obj.task_list_id else None
    info = (
        db.session.get(InformationPiece, obj.information_id)
        if obj.information_id
        else None
    )
    data = obj.to_dict(task_list=task_list, tasks=tasks, information=info)
    data["tags"] = tags_for_object(obj.id)
    data["connections"] = connection_dicts_for_object(obj)
    # Legacy alias for older clients.
    data["links"] = data["connections"]
    return data


@objects_bp.route("/objects/graph", methods=["GET"])
def workspace_graph():
    workspace_id = request.args.get("workspace_id", type=int) or default_workspace_id()
    if not workspace_id:
        return jsonify({"error": "workspace_id is required"}), 400
    return jsonify(build_workspace_graph(workspace_id))


@objects_bp.route("/objects/graph/positions", methods=["PUT"])
def save_graph_positions():
    data = request.get_json(silent=True) or {}
    workspace_id = data.get("workspace_id") or default_workspace_id()
    if not workspace_id:
        return jsonify({"error": "workspace_id is required"}), 400
    updated = apply_diagram_positions(int(workspace_id), data.get("positions") or [])
    db.session.commit()
    return jsonify({"updated": updated})


@objects_bp.route("/files/<int:file_id>/objects", methods=["GET"])
def list_objects(file_id):
    get_or_404(File, file_id)
    embeds = (
        ObjectEmbed.query.filter_by(file_id=file_id)
        .order_by(ObjectEmbed.sort_key, ObjectEmbed.id)
        .all()
    )
    return jsonify([_resolve_embed(e) for e in embeds])


@objects_bp.route("/files/<int:file_id>/description-links", methods=["GET"])
def list_file_description_links(file_id):
    get_or_404(File, file_id)
    rows = Link.query.filter_by(
        kind="description",
        target_type="file",
        target_id=file_id,
    ).all()
    out = []
    for link in rows:
        data = link.to_dict()
        peer = db.session.get(ObjectEmbed, link.source_id)
        info = (
            db.session.get(InformationPiece, peer.information_id)
            if peer is not None and peer.information_id
            else None
        )
        data["peer"] = {
            "type": "info",
            "id": link.source_id,
            "title": (info.title if info else "") or "Info",
            "body": (info.body if info else "") or "",
            "file_id": peer.file_id if peer else None,
        }
        out.append(data)
    return jsonify(out)


@objects_bp.route("/files/<int:file_id>/objects", methods=["POST"])
def create_object(file_id):
    file = get_or_404(File, file_id)
    data = request.get_json(silent=True) or {}
    type_ = data.get("type")
    api_type, _is_chart = normalize_create_type(type_ or "")
    if api_type not in _OBJECT_TYPES and (type_ or "") != "graph":
        return jsonify({"error": f"type must be one of {sorted(_OBJECT_TYPES)}"}), 400

    block_index = data.get("block_index")
    if block_index is None and data.get("index") is not None:
        block_index = data.get("index")
    if block_index is None and data.get("offset") is not None:
        block_index = data.get("offset")

    try:
        embed = create_embed_in_file(
            file,
            type_=type_ or "",
            title=data.get("title") or "",
            body=data.get("body") or "",
            payload=data.get("payload"),
            block_index=block_index,
            sort_key=data.get("sort_key"),
        )
    except ValueError as err:
        return jsonify({"error": str(err)}), 400

    db.session.commit()
    return jsonify(_resolve_embed(embed)), 201


@objects_bp.route("/objects/<int:object_id>", methods=["GET"])
def get_object(object_id):
    embed = get_or_404(ObjectEmbed, object_id)
    return jsonify(_resolve_embed(embed))


@objects_bp.route("/objects/<int:object_id>", methods=["PATCH"])
def update_object(object_id):
    embed = get_or_404(ObjectEmbed, object_id)
    data = request.get_json(silent=True) or {}
    if "sort_key" in data:
        embed.sort_key = data["sort_key"]
    if "anchor" in data:
        embed.anchor = data["anchor"]
    if "diagram_x" in data:
        embed.diagram_x = None if data["diagram_x"] is None else float(data["diagram_x"])
    if "diagram_y" in data:
        embed.diagram_y = None if data["diagram_y"] is None else float(data["diagram_y"])
    if "payload" in data and embed.type in {"image", "table"}:
        payload = data["payload"] or {}
        if embed.type == "table":
            from areas.objects.services.table_payload import normalize_table_payload

            embed.payload = normalize_table_payload(payload)
        else:
            embed.payload = payload
    db.session.commit()
    return jsonify(_resolve_embed(embed))


@objects_bp.route("/objects/<int:object_id>", methods=["DELETE"])
def delete_object(object_id):
    embed = get_or_404(ObjectEmbed, object_id)
    delete_object_embed_cascade(embed, remove_from_document=True)
    db.session.commit()
    return "", 204


@objects_bp.route("/objects/<int:object_id>/links", methods=["GET"])
def list_object_links(object_id):
    embed = get_or_404(ObjectEmbed, object_id)
    return jsonify(connection_dicts_for_object(embed))


@objects_bp.route("/objects/<int:object_id>/links", methods=["POST"])
def create_object_link(object_id):
    embed = get_or_404(ObjectEmbed, object_id)
    data = request.get_json(silent=True) or {}
    kind = data.get("kind") or "related"
    if kind not in LINK_KINDS:
        return jsonify({"error": f"kind must be one of {sorted(LINK_KINDS)}"}), 400

    workspace_id = _workspace_for_object(embed) or default_workspace_id()
    if not workspace_id:
        return jsonify({"error": "workspace_id required"}), 400

    if kind == "description":
        if embed.type != "info":
            return jsonify({"error": "description links require an info source"}), 400
        anchor = data.get("anchor")
        if not isinstance(anchor, dict) or not anchor.get("file_id"):
            return jsonify({"error": "anchor.file_id required for description"}), 400
        file_id = int(anchor["file_id"])
        get_or_404(File, file_id)
        link = Link(
            workspace_id=workspace_id,
            source_type="info",
            source_id=embed.id,
            target_type="file",
            target_id=file_id,
            kind="description",
            anchor=anchor,
            label=data.get("label"),
        )
        db.session.add(link)
        db.session.commit()
        return jsonify(link.to_dict()), 201

    # related: target is another object
    target_object_id = data.get("target_object_id") or data.get("target_id")
    if target_object_id is None:
        return jsonify({"error": "target_object_id required"}), 400
    target = get_or_404(ObjectEmbed, int(target_object_id))
    if target.id == embed.id:
        return jsonify({"error": "cannot link an object to itself"}), 400

    link = Link(
        workspace_id=workspace_id,
        source_type=embed.type,
        source_id=embed.id,
        target_type=target.type,
        target_id=target.id,
        kind="related",
        label=data.get("label"),
    )
    db.session.add(link)
    db.session.commit()
    return jsonify(link.to_dict()), 201


@objects_bp.route("/objects/<int:object_id>/links/<int:link_id>", methods=["DELETE"])
def delete_object_link(object_id, link_id):
    get_or_404(ObjectEmbed, object_id)
    link = Link.query.filter_by(id=link_id).first()
    if link is None:
        return jsonify({"error": "not found"}), 404
    touches = (
        (link.source_type in OBJECT_LINK_TYPES and link.source_id == object_id)
        or (link.target_type in OBJECT_LINK_TYPES and link.target_id == object_id)
        or (
            (link.kind or "related") == "description"
            and link.source_type == "info"
            and link.source_id == object_id
        )
    )
    if not touches:
        return jsonify({"error": "not found"}), 404
    db.session.delete(link)
    db.session.commit()
    return "", 204


@objects_bp.route("/objects/<int:object_id>/tags", methods=["GET"])
def list_object_tags(object_id):
    get_or_404(ObjectEmbed, object_id)
    return jsonify(tags_for_object(object_id))


@objects_bp.route("/objects/<int:object_id>/tags", methods=["PUT"])
def replace_object_tags(object_id):
    get_or_404(ObjectEmbed, object_id)
    data = request.get_json(silent=True) or {}
    tag_ids = data.get("tag_ids") or []
    EntityTag.query.filter_by(
        entity_type="object", entity_id=object_id
    ).delete(synchronize_session=False)
    for tag_id in tag_ids:
        db.session.add(
            EntityTag(
                tag_id=int(tag_id),
                entity_type="object",
                entity_id=object_id,
            )
        )
    db.session.commit()
    return jsonify(tags_for_object(object_id))
