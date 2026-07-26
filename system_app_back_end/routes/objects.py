from flask import Blueprint, jsonify, request

from models import File, FileVersion, InformationPiece, ObjectEmbed, Task, db
from routes.helpers import get_or_404
from services.delete_cascade import delete_object_embed_cascade
from services.document_body import insert_marker, marker_for, sync_anchors

objects_bp = Blueprint("objects", __name__)


def _resolve_embed(obj: ObjectEmbed) -> dict:
    task = db.session.get(Task, obj.task_id) if obj.task_id else None
    info = (
        db.session.get(InformationPiece, obj.information_id)
        if obj.information_id
        else None
    )
    return obj.to_dict(task=task, information=info)


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
    if type_ not in {"task", "information"}:
        return jsonify({"error": "type must be task or information"}), 400

    if type_ == "task":
        title = data.get("title") or "New task"
        entity = Task(title=title, list_order_index=data.get("list_order_index", 0))
        db.session.add(entity)
        db.session.flush()
        embed = ObjectEmbed(file_id=file.id, type="task", task_id=entity.id)
    else:
        entity = InformationPiece(
            title=data.get("title") or "",
            body=data.get("body") or "",
            metadata_=data.get("metadata") or {},
        )
        db.session.add(entity)
        db.session.flush()
        embed = ObjectEmbed(
            file_id=file.id, type="information", information_id=entity.id
        )

    db.session.add(embed)
    db.session.flush()

    entity_id = entity.id
    marker = marker_for(type_, entity_id)
    file.body = insert_marker(file.body or "", marker, line=data.get("line"))
    embed.anchor = {"kind": "marker", "marker": marker}
    embed.sort_key = data.get("sort_key", embed.id)
    sync_anchors(file.body or "", [embed])
    db.session.commit()
    return jsonify(_resolve_embed(embed)), 201


@objects_bp.route("/objects/<int:object_id>", methods=["PATCH"])
def update_object(object_id):
    embed = get_or_404(ObjectEmbed, object_id)
    data = request.get_json(silent=True) or {}
    if "sort_key" in data:
        embed.sort_key = data["sort_key"]
    if "anchor" in data:
        embed.anchor = data["anchor"]
    db.session.commit()
    return jsonify(_resolve_embed(embed))


@objects_bp.route("/objects/<int:object_id>", methods=["DELETE"])
def delete_object(object_id):
    embed = get_or_404(ObjectEmbed, object_id)
    delete_object_embed_cascade(embed, remove_from_body=True)
    db.session.commit()
    return "", 204
