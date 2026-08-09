from flask import Blueprint, jsonify, request

from models import File, Topic, db
from shared.helpers import active_query, apply_updates, get_or_404
from areas.objects.services.delete_cascade import delete_file_cascade
from areas.files.services.document_v3 import empty_document_json, validate_document
from areas.files.services.document_promote import promote_legacy_embeds
from areas.files.services.file_versions import save_file_version

files_bp = Blueprint("files", __name__)


def _file_response(file: File):
    promote_legacy_embeds(file)
    db.session.commit()
    return jsonify(file.to_dict())


@files_bp.route("/files", methods=["GET"])
def list_files():
    files = active_query(File).order_by(File.order_index, File.id).all()
    return jsonify([f.to_dict(include_document=False) for f in files])


@files_bp.route("/files/<int:file_id>", methods=["GET"])
def get_file(file_id):
    file = get_or_404(File, file_id)
    return _file_response(file)


@files_bp.route("/topics/<int:topic_id>/files", methods=["GET"])
def list_files_by_topic(topic_id):
    get_or_404(Topic, topic_id)
    files = (
        active_query(File)
        .filter_by(topic_id=topic_id)
        .order_by(File.order_index, File.id)
        .all()
    )
    # Documents included: the app renders every file of a topic inline from this
    # one response. Without them the editor opens empty and the first keystroke
    # saves that emptiness over the stored document.
    return jsonify([f.to_dict(include_document=True) for f in files])


@files_bp.route("/topics/<int:topic_id>/archive/files", methods=["GET"])
def list_archived_files_by_topic(topic_id):
    get_or_404(Topic, topic_id)
    files = (
        File.query.filter_by(topic_id=topic_id)
        .filter(File.archived_at.isnot(None))
        .order_by(File.archived_at.desc(), File.id.desc())
        .all()
    )
    return jsonify([f.to_dict(include_document=True) for f in files])


@files_bp.route("/files", methods=["POST"])
def create_file():
    data = request.get_json(silent=True) or {}
    if not data.get("name") or not data.get("topic_id"):
        return jsonify({"error": "name and topic_id are required"}), 400
    get_or_404(Topic, data["topic_id"])

    document_json = data.get("document_json") or empty_document_json()
    file = File(
        topic_id=data["topic_id"],
        name=data["name"],
        document_json=document_json,
        order_index=data.get("order_index", 0),
        meta=data.get("meta") or {},
    )
    db.session.add(file)
    db.session.commit()
    return jsonify(file.to_dict()), 201


@files_bp.route("/files/<int:file_id>", methods=["PATCH"])
def update_file(file_id):
    file = get_or_404(File, file_id)
    data = request.get_json(silent=True) or {}

    if "document_json" in data and data["document_json"] != file.document_json:
        save_file_version(file, source="user")
        try:
            validate_document(data["document_json"])
        except ValueError as error:
            return jsonify({"error": str(error)}), 400

    apply_updates(
        file,
        data,
        {
            "topic_id",
            "name",
            "document_json",
            "order_index",
            "meta",
            "archived_at",
        },
        datetime_fields={"archived_at"},
    )
    promote_legacy_embeds(file)
    db.session.commit()
    return jsonify(file.to_dict())


@files_bp.route("/files/<int:file_id>", methods=["DELETE"])
def delete_file(file_id):
    get_or_404(File, file_id)
    delete_file_cascade(file_id)
    db.session.commit()
    return "", 204
