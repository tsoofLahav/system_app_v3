from datetime import datetime

from flask import Blueprint, jsonify, request

from models import Block, File, Part, Topic, db
from routes.helpers import active_query, apply_updates, get_or_404
from services.automation_dispatcher import dispatch_file_changed
from services.part_defaults import PART_PLACEMENT_FILE_TYPES
from services.part_placement import (
    create_part_for_topic,
    part_ids_in_file,
    place_part_in_file,
)
from services.part_resolver import part_by_id

parts_bp = Blueprint("parts", __name__)


def _sync_part_header_names(part: Part) -> None:
    blocks = (
        Block.query.filter_by(part_id=part.id)
        .filter(Block.archived_at.is_(None))
        .filter(Block.type == "header")
        .all()
    )
    for block in blocks:
        content = dict(block.content or {})
        content["text"] = part.name
        content["part_id"] = part.id
        block.content = content


@parts_bp.route("/topics/<int:topic_id>/parts", methods=["GET"])
def list_parts_for_topic(topic_id):
    get_or_404(Topic, topic_id)
    parts = (
        active_query(Part)
        .filter_by(topic_id=topic_id)
        .order_by(Part.order_index, Part.id)
        .all()
    )
    return jsonify([part.to_dict() for part in parts])


@parts_bp.route("/topics/<int:topic_id>/parts", methods=["POST"])
def create_part(topic_id):
    topic = get_or_404(Topic, topic_id)
    data = request.get_json(silent=True) or {}
    name = data.get("name")
    if not name or not str(name).strip():
        return jsonify({"error": "name is required"}), 400

    file_id = data.get("file_id")
    file = None
    if file_id is not None:
        file = get_or_404(File, file_id)
        if file.topic_id != topic.id:
            return jsonify({"error": "file does not belong to topic"}), 400

    try:
        result = create_part_for_topic(
            topic,
            name=str(name).strip(),
            file=file,
            insert_after_block_id=data.get("insert_after_block_id"),
            insert_index=data.get("insert_index"),
        )
    except ValueError as error:
        return jsonify({"error": str(error)}), 400

    db.session.commit()
    if file is not None:
        dispatch_file_changed(file.id, "part_placed", {"part_id": result["part"]["id"]})
    return jsonify(result), 201


@parts_bp.route("/parts/<int:part_id>", methods=["GET"])
def get_part(part_id):
    return jsonify(get_or_404(Part, part_id).to_dict())


@parts_bp.route("/parts/<int:part_id>", methods=["PATCH"])
def update_part(part_id):
    part = get_or_404(Part, part_id)
    data = request.get_json(silent=True) or {}
    apply_updates(
        part,
        data,
        {"name", "order_index", "archived_at"},
        datetime_fields={"archived_at"},
    )
    if "name" in data:
        _sync_part_header_names(part)
    db.session.commit()
    return jsonify(part.to_dict())


@parts_bp.route("/parts/<int:part_id>", methods=["DELETE"])
def archive_part(part_id):
    part = get_or_404(Part, part_id)
    part.archived_at = datetime.utcnow()
    db.session.commit()
    return "", 204


@parts_bp.route("/files/<int:file_id>/parts", methods=["POST"])
def place_part_in_file_route(file_id):
    file = get_or_404(File, file_id)
    if file.type not in PART_PLACEMENT_FILE_TYPES:
        return jsonify({"error": "part placement is not supported for this file type"}), 400

    data = request.get_json(silent=True) or {}
    part_id = data.get("part_id")
    name = data.get("name")

    try:
        if part_id is not None:
            part = part_by_id(int(part_id))
            if part is None or part.topic_id != file.topic_id:
                return jsonify({"error": "part not found for topic"}), 404
            result = place_part_in_file(
                file,
                part=part,
                insert_after_block_id=data.get("insert_after_block_id"),
                insert_index=data.get("insert_index"),
            )
        else:
            if not name or not str(name).strip():
                return jsonify({"error": "name is required when part_id is omitted"}), 400
            topic = get_or_404(Topic, file.topic_id)
            result = create_part_for_topic(
                topic,
                name=str(name).strip(),
                file=file,
                insert_after_block_id=data.get("insert_after_block_id"),
                insert_index=data.get("insert_index"),
            )
    except ValueError as error:
        return jsonify({"error": str(error)}), 400

    db.session.commit()
    dispatch_file_changed(file.id, "part_placed", {"part_id": result["part"]["id"]})
    return jsonify(result), 201


@parts_bp.route("/files/<int:file_id>/part-ids", methods=["GET"])
def list_part_ids_in_file(file_id):
    get_or_404(File, file_id)
    return jsonify(sorted(part_ids_in_file(file_id)))
