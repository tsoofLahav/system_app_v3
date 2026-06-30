from flask import Blueprint, jsonify, request

from models import File, db
from routes.helpers import active_query, apply_updates, get_or_404
from services.automation_dispatcher import dispatch_file_changed
from services.delete_cascade import delete_file_cascade

files_bp = Blueprint("files", __name__)


@files_bp.route("/files", methods=["GET"])
def list_files():
    files = active_query(File).order_by(File.order_index, File.id).all()
    return jsonify([f.to_dict() for f in files])


@files_bp.route("/files/<int:file_id>", methods=["GET"])
def get_file(file_id):
    return jsonify(get_or_404(File, file_id).to_dict())


@files_bp.route("/topics/<int:topic_id>/files", methods=["GET"])
def list_files_by_topic(topic_id):
    files = (
        active_query(File)
        .filter_by(topic_id=topic_id)
        .order_by(File.order_index, File.id)
        .all()
    )
    return jsonify([f.to_dict() for f in files])


@files_bp.route("/files", methods=["POST"])
def create_file():
    data = request.get_json(silent=True) or {}
    if not data.get("name") or not data.get("type"):
        return jsonify({"error": "name and type are required"}), 400

    file = File(
        topic_id=data.get("topic_id"),
        name=data["name"],
        type=data["type"],
        order_index=data.get("order_index"),
        is_main=data.get("is_main"),
    )
    db.session.add(file)
    db.session.commit()
    return jsonify(file.to_dict()), 201


@files_bp.route("/files/<int:file_id>", methods=["PATCH"])
def update_file(file_id):
    file = get_or_404(File, file_id)
    data = request.get_json(silent=True) or {}
    apply_updates(
        file,
        data,
        {"topic_id", "name", "type", "order_index", "is_main", "archived_at"},
        datetime_fields={"archived_at"},
    )
    db.session.commit()
    dispatch_file_changed(file_id, "file_updated")
    return jsonify(file.to_dict())


@files_bp.route("/files/<int:file_id>", methods=["DELETE"])
def delete_file(file_id):
    get_or_404(File, file_id)
    delete_file_cascade(file_id)
    db.session.commit()
    return "", 204
