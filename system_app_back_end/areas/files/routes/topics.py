from flask import Blueprint, jsonify, request

from models import EntityTag, Tag, Topic, db
from shared.helpers import active_query, apply_updates, get_or_404
from shared.bootstrap import default_workspace_id
from areas.objects.services.delete_cascade import delete_topic_cascade

topics_bp = Blueprint("topics", __name__)


def _tags_for_topic(topic_id: int) -> list[dict]:
    rows = (
        db.session.query(Tag)
        .join(EntityTag, EntityTag.tag_id == Tag.id)
        .filter(EntityTag.entity_type == "topic", EntityTag.entity_id == topic_id)
        .all()
    )
    return [t.to_dict() for t in rows]


@topics_bp.route("/topics", methods=["GET"])
def list_topics():
    query = active_query(Topic)
    workspace_id = request.args.get("workspace_id", type=int)
    if workspace_id:
        query = query.filter_by(workspace_id=workspace_id)
    topics = query.order_by(Topic.order_index, Topic.id).all()
    result = []
    for topic in topics:
        data = topic.to_dict()
        data["tags"] = _tags_for_topic(topic.id)
        result.append(data)
    return jsonify(result)


@topics_bp.route("/topics/<int:topic_id>", methods=["GET"])
def get_topic(topic_id):
    topic = get_or_404(Topic, topic_id)
    data = topic.to_dict()
    data["tags"] = _tags_for_topic(topic.id)
    return jsonify(data)


@topics_bp.route("/topics", methods=["POST"])
def create_topic():
    data = request.get_json(silent=True) or {}
    if not data.get("name"):
        return jsonify({"error": "name is required"}), 400
    workspace_id = data.get("workspace_id") or default_workspace_id()
    if not workspace_id:
        return jsonify({"error": "workspace_id is required"}), 400

    topic = Topic(
        workspace_id=workspace_id,
        name=data["name"],
        icon=data.get("icon"),
        color=data.get("color"),
        order_index=data.get("order_index", 0),
        file_layout=data.get("file_layout") or "single",
    )
    db.session.add(topic)
    db.session.flush()

    tag_ids = data.get("tag_ids") or []
    for tag_id in tag_ids:
        db.session.add(
            EntityTag(tag_id=int(tag_id), entity_type="topic", entity_id=topic.id)
        )

    db.session.commit()
    result = topic.to_dict()
    result["tags"] = _tags_for_topic(topic.id)
    return jsonify(result), 201


@topics_bp.route("/topics/<int:topic_id>", methods=["PATCH"])
def update_topic(topic_id):
    topic = get_or_404(Topic, topic_id)
    data = request.get_json(silent=True) or {}
    apply_updates(
        topic,
        data,
        {"name", "icon", "color", "order_index", "file_layout", "archived_at"},
        datetime_fields={"archived_at"},
    )

    if "tag_ids" in data:
        EntityTag.query.filter_by(entity_type="topic", entity_id=topic.id).delete(
            synchronize_session=False
        )
        for tag_id in data.get("tag_ids") or []:
            db.session.add(
                EntityTag(tag_id=int(tag_id), entity_type="topic", entity_id=topic.id)
            )

    db.session.commit()
    result = topic.to_dict()
    result["tags"] = _tags_for_topic(topic.id)
    return jsonify(result)


@topics_bp.route("/topics/<int:topic_id>", methods=["DELETE"])
def delete_topic(topic_id):
    get_or_404(Topic, topic_id)
    delete_topic_cascade(topic_id)
    db.session.commit()
    return "", 204
