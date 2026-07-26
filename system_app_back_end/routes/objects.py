from flask import Blueprint, jsonify, request

from models import File, InformationPiece, Link, ObjectEmbed, TaskList, Topic, db
from routes.helpers import get_or_404
from services.bootstrap import default_workspace_id
from services.delete_cascade import delete_object_embed_cascade
from services.document_v3 import (
    insert_embed_block,
    parse_document,
    remove_object_embeds,
    serialize_document,
    sync_object_anchors,
)
from services.document_promote import promote_legacy_embeds
from services.task_list_order import tasks_for_list

objects_bp = Blueprint("objects", __name__)

_OBJECT_TYPES = {"task_list", "info", "image", "graph"}


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
    if obj.type == "info" and obj.information_id:
        links = Link.query.filter_by(
            source_type="info", source_id=obj.information_id
        ).all()
        data["links"] = [link.to_dict() for link in links]
    return data


def _create_embed_entity(type_: str, data: dict) -> ObjectEmbed:
    if type_ == "task_list":
        task_list = TaskList()
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
    return ObjectEmbed(
        file_id=data["file_id"],
        type=type_,
        payload=payload,
    )


@objects_bp.route("/files/<int:file_id>/objects", methods=["GET"])
def list_objects(file_id):
    get_or_404(File, file_id)
    embeds = (
        ObjectEmbed.query.filter_by(file_id=file_id)
        .order_by(ObjectEmbed.sort_key, ObjectEmbed.id)
        .all()
    )
    return jsonify([_resolve_embed(e) for e in embeds])


@objects_bp.route("/files/<int:file_id>/objects", methods=["POST"])
def create_object(file_id):
    file = get_or_404(File, file_id)
    data = request.get_json(silent=True) or {}
    type_ = data.get("type")
    if type_ not in _OBJECT_TYPES:
        return jsonify({"error": f"type must be one of {sorted(_OBJECT_TYPES)}"}), 400

    embed = _create_embed_entity(type_, {**data, "file_id": file.id})
    db.session.add(embed)
    db.session.flush()

    block_index = data.get("block_index")
    if block_index is None and data.get("index") is not None:
        block_index = data.get("index")
    if block_index is None and data.get("offset") is not None:
        block_index = data.get("offset")

    file.document_json = insert_embed_block(
        file.document_json or "",
        embed.id,
        block_index=block_index,
    )
    doc = parse_document(file.document_json)
    hit = next(
        (b for b in doc["blocks"] if b.get("object_id") == embed.id),
        None,
    )
    if hit:
        embed.anchor = {"kind": "embed", "block_id": hit["id"]}
    embed.sort_key = data.get("sort_key", embed.id)
    sync_object_anchors(file.document_json or "", [embed])
    promote_legacy_embeds(file)
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
    if "payload" in data and embed.type in {"image", "graph"}:
        embed.payload = data["payload"] or {}
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
    if embed.type != "info" or not embed.information_id:
        return jsonify([])
    rows = Link.query.filter_by(
        source_type="info", source_id=embed.information_id
    ).all()
    return jsonify([r.to_dict() for r in rows])


@objects_bp.route("/objects/<int:object_id>/links", methods=["POST"])
def create_object_link(object_id):
    embed = get_or_404(ObjectEmbed, object_id)
    if embed.type != "info" or not embed.information_id:
        return jsonify({"error": "links only supported for info objects"}), 400
    data = request.get_json(silent=True) or {}
    target_type = data.get("target_type")
    target_id = data.get("target_id")
    if not target_type or target_id is None:
        return jsonify({"error": "target_type and target_id required"}), 400

    workspace_id = _workspace_for_object(embed) or default_workspace_id()
    link = Link(
        workspace_id=workspace_id,
        source_type="info",
        source_id=embed.information_id,
        target_type=target_type,
        target_id=int(target_id),
        label=data.get("label"),
    )
    db.session.add(link)
    db.session.commit()
    return jsonify(link.to_dict()), 201


@objects_bp.route("/objects/<int:object_id>/links/<int:link_id>", methods=["DELETE"])
def delete_object_link(object_id, link_id):
    embed = get_or_404(ObjectEmbed, object_id)
    if embed.type != "info" or not embed.information_id:
        return jsonify({"error": "not found"}), 404
    link = Link.query.filter_by(
        id=link_id, source_type="info", source_id=embed.information_id
    ).first()
    if link is None:
        return jsonify({"error": "not found"}), 404
    db.session.delete(link)
    db.session.commit()
    return "", 204
