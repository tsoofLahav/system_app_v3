from flask import Blueprint, jsonify, request

from models import Topic, db
from routes.helpers import active_query, apply_updates, get_or_404
from services.delete_cascade import delete_topic_cascade
from services.details_lookup import list_details_blocks_for_topic

topics_bp = Blueprint("topics", __name__)


@topics_bp.route("/topics", methods=["GET"])
def list_topics():
    topics = active_query(Topic).order_by(Topic.id).all()
    return jsonify([t.to_dict() for t in topics])


@topics_bp.route("/topics/<int:topic_id>", methods=["GET"])
def get_topic(topic_id):
    return jsonify(get_or_404(Topic, topic_id).to_dict())


@topics_bp.route("/topics/<int:topic_id>/details-blocks", methods=["GET"])
def list_topic_details_blocks(topic_id):
    get_or_404(Topic, topic_id)
    return jsonify(list_details_blocks_for_topic(topic_id))


@topics_bp.route("/topics", methods=["POST"])
def create_topic():
    data = request.get_json(silent=True) or {}
    if not data.get("name") or not data.get("type"):
        return jsonify({"error": "name and type are required"}), 400

    topic = Topic(
        name=data["name"],
        type=data["type"],
        icon=data.get("icon"),
        color=data.get("color"),
        parent_id=data.get("parent_id"),
    )
    db.session.add(topic)
    db.session.commit()
    return jsonify(topic.to_dict()), 201


@topics_bp.route("/topics/<int:topic_id>", methods=["PATCH"])
def update_topic(topic_id):
    topic = get_or_404(Topic, topic_id)
    data = request.get_json(silent=True) or {}
    apply_updates(
        topic,
        data,
        {"name", "type", "icon", "color", "parent_id", "archived_at"},
        datetime_fields={"archived_at"},
    )
    db.session.commit()
    return jsonify(topic.to_dict())


@topics_bp.route("/topics/<int:topic_id>/duplicate", methods=["POST"])
def duplicate_topic_route(topic_id):
    topic = get_or_404(Topic, topic_id)
    data = request.get_json(silent=True) or {}
    name = data.get("name")
    try:
        from services.duplicate_topic import duplicate_topic

        duplicate = duplicate_topic(topic, name=name)
    except ValueError as error:
        return jsonify({"error": str(error)}), 400
    db.session.commit()
    return jsonify(duplicate.to_dict()), 201


@topics_bp.route("/topics/<int:topic_id>", methods=["DELETE"])
def delete_topic(topic_id):
    get_or_404(Topic, topic_id)
    delete_topic_cascade(topic_id)
    db.session.commit()
    return "", 204
