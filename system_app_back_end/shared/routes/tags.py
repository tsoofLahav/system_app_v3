from flask import Blueprint, jsonify, request

from models import EntityTag, Tag, db
from shared.helpers import get_or_404, apply_updates
from shared.bootstrap import default_workspace_id
from areas.objects.services.delete_cascade import delete_tag_cascade

tags_bp = Blueprint("tags", __name__)


@tags_bp.route("/tags", methods=["GET"])
def list_tags():
    workspace_id = request.args.get("workspace_id", type=int) or default_workspace_id()
    query = Tag.query
    if workspace_id:
        query = query.filter_by(workspace_id=workspace_id)
    tags = query.order_by(Tag.name).all()
    return jsonify([t.to_dict() for t in tags])


@tags_bp.route("/tags", methods=["POST"])
def create_tag():
    data = request.get_json(silent=True) or {}
    if not data.get("name"):
        return jsonify({"error": "name is required"}), 400
    workspace_id = data.get("workspace_id") or default_workspace_id()
    if not workspace_id:
        return jsonify({"error": "workspace_id is required"}), 400
    tag = Tag(
        workspace_id=workspace_id,
        name=data["name"].strip(),
        color=data.get("color"),
        icon=data.get("icon"),
    )
    db.session.add(tag)
    db.session.commit()
    return jsonify(tag.to_dict()), 201


@tags_bp.route("/tags/<int:tag_id>", methods=["PATCH"])
def update_tag(tag_id):
    tag = get_or_404(Tag, tag_id)
    data = request.get_json(silent=True) or {}
    apply_updates(tag, data, {"name", "color", "icon"})
    if "name" in data and data["name"] is not None:
        tag.name = str(data["name"]).strip()
    db.session.commit()
    return jsonify(tag.to_dict())


@tags_bp.route("/tags/<int:tag_id>", methods=["DELETE"])
def delete_tag(tag_id):
    get_or_404(Tag, tag_id)
    delete_tag_cascade(tag_id)
    db.session.commit()
    return "", 204


@tags_bp.route("/tags/assign", methods=["POST"])
def assign_tag():
    data = request.get_json(silent=True) or {}
    for field in ("tag_id", "entity_type", "entity_id"):
        if field not in data:
            return jsonify({"error": f"{field} is required"}), 400
    existing = EntityTag.query.filter_by(
        tag_id=data["tag_id"],
        entity_type=data["entity_type"],
        entity_id=data["entity_id"],
    ).first()
    if existing:
        return jsonify(existing.to_dict())
    row = EntityTag(
        tag_id=data["tag_id"],
        entity_type=data["entity_type"],
        entity_id=data["entity_id"],
    )
    db.session.add(row)
    db.session.commit()
    return jsonify(row.to_dict()), 201


@tags_bp.route("/tags/assign", methods=["DELETE"])
def unassign_tag():
    data = request.get_json(silent=True) or {}
    query = EntityTag.query
    for field in ("tag_id", "entity_type", "entity_id"):
        if field in data:
            query = query.filter_by(**{field: data[field]})
    query.delete(synchronize_session=False)
    db.session.commit()
    return "", 204
