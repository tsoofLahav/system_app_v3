"""User-defined topic types: name, optional live template topic."""

from flask import Blueprint, jsonify, request

from models import Automation, Topic, TopicType, db
from shared.bootstrap import default_workspace_id
from shared.helpers import apply_updates, get_or_404
from areas.files.services.template_slots import stamp_template_slots

topic_types_bp = Blueprint("topic_types", __name__)


def _workspace_types(workspace_id: int) -> list[TopicType]:
    return (
        TopicType.query.filter_by(workspace_id=workspace_id)
        .order_by(TopicType.order_index, TopicType.id)
        .all()
    )


@topic_types_bp.route("/topic-types", methods=["GET"])
def list_topic_types():
    workspace_id = request.args.get("workspace_id", type=int) or default_workspace_id()
    if not workspace_id:
        return jsonify({"error": "workspace_id is required"}), 400
    return jsonify([row.to_dict() for row in _workspace_types(workspace_id)])


@topic_types_bp.route("/topic-types", methods=["POST"])
def create_topic_type():
    data = request.get_json(silent=True) or {}
    name = str(data.get("name") or "").strip()
    if not name:
        return jsonify({"error": "name is required"}), 400
    workspace_id = data.get("workspace_id") or default_workspace_id()
    if not workspace_id:
        return jsonify({"error": "workspace_id is required"}), 400

    existing = TopicType.query.filter_by(
        workspace_id=workspace_id, name=name
    ).first()
    if existing:
        return jsonify({"error": "a type with that name already exists"}), 409

    siblings = _workspace_types(workspace_id)
    order = data.get("order_index")
    if order is None:
        order = (siblings[-1].order_index + 1) if siblings else 0

    row = TopicType(
        workspace_id=workspace_id,
        name=name,
        order_index=int(order),
    )
    db.session.add(row)
    db.session.commit()
    return jsonify(row.to_dict()), 201


@topic_types_bp.route("/topic-types/<int:type_id>", methods=["PATCH"])
def update_topic_type(type_id):
    row = get_or_404(TopicType, type_id)
    data = request.get_json(silent=True) or {}

    if "name" in data:
        name = str(data.get("name") or "").strip()
        if not name:
            return jsonify({"error": "name is required"}), 400
        clash = TopicType.query.filter(
            TopicType.workspace_id == row.workspace_id,
            TopicType.name == name,
            TopicType.id != row.id,
        ).first()
        if clash:
            return jsonify({"error": "a type with that name already exists"}), 409
        row.name = name

    apply_updates(row, data, {"order_index"})

    if "template_topic_id" in data:
        raw = data.get("template_topic_id")
        if raw in (None, ""):
            row.template_topic_id = None
        else:
            topic = db.session.get(Topic, int(raw))
            if topic is None or int(topic.workspace_id) != int(row.workspace_id):
                return jsonify({"error": "template topic not found"}), 400
            if topic.topic_type_id not in (None, row.id):
                return jsonify({"error": "template must be a topic of this type"}), 400
            if topic.topic_type_id is None:
                topic.topic_type_id = row.id
            row.template_topic_id = topic.id
            stamp_template_slots(topic)

    db.session.commit()
    return jsonify(row.to_dict())


@topic_types_bp.route("/topic-types/<int:type_id>", methods=["DELETE"])
def delete_topic_type(type_id):
    row = get_or_404(TopicType, type_id)
    in_use = Topic.query.filter_by(topic_type_id=row.id).count()
    if in_use:
        return jsonify({"error": "type is still used by topics"}), 409

    for automation in Automation.query.filter_by(workspace_id=row.workspace_id).all():
        scope = automation.scope or {}
        if (
            scope.get("kind") == "topic_type"
            and scope.get("topic_type_id") is not None
            and int(scope["topic_type_id"]) == row.id
        ):
            return jsonify({"error": "type is still used by automations"}), 409
    db.session.delete(row)
    db.session.commit()
    return "", 204
