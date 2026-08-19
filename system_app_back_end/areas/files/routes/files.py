from flask import Blueprint, jsonify, request

from models import File, Topic, db
from shared.helpers import active_query, apply_updates, get_or_404
from areas.objects.services.delete_cascade import (
    delete_file_cascade,
    purge_unreferenced_embeds_for_file,
)
from areas.files.services import file_ops
from areas.files.services.archive_files import list_archived_files_for_topic
from areas.files.services.document_agent_text import agent_text_from_document_json
from areas.files.services.document_v3 import validate_document
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


@files_bp.route("/files/<int:file_id>/agent-text", methods=["GET"])
def get_file_agent_text(file_id):
    file = get_or_404(File, file_id)
    return jsonify(
        {
            "agent_text": agent_text_from_document_json(
                file.document_json,
                file_id=file.id,
            )
        }
    )


@files_bp.route("/topics/<int:topic_id>/archive/files", methods=["GET"])
def list_archived_files_by_topic(topic_id):
    limit = request.args.get("limit", default=24, type=int)
    offset = request.args.get("offset", default=0, type=int)
    q = request.args.get("q", type=str)
    payload = list_archived_files_for_topic(
        topic_id,
        limit=limit if limit is not None else 24,
        offset=offset or 0,
        q=q,
    )
    if payload is None:
        return jsonify({"error": "topic not found"}), 404
    return jsonify(payload)


@files_bp.route("/files", methods=["POST"])
def create_file():
    data = request.get_json(silent=True) or {}
    if not data.get("name") or not data.get("topic_id"):
        return jsonify({"error": "name and topic_id are required"}), 400
    get_or_404(Topic, data["topic_id"])

    file = file_ops.create_file(
        topic_id=data["topic_id"],
        name=data["name"],
        document_json=data.get("document_json"),
        order_index=data.get("order_index", 0),
        meta=data.get("meta"),
    )
    db.session.commit()
    return jsonify(file.to_dict()), 201


@files_bp.route("/files/<int:file_id>", methods=["PATCH"])
def update_file(file_id):
    file = get_or_404(File, file_id)
    data = request.get_json(silent=True) or {}

    document_changed = (
        "document_json" in data and data["document_json"] != file.document_json
    )
    if document_changed:
        save_file_version(file, source="user")
        try:
            validate_document(data["document_json"])
        except ValueError as error:
            return jsonify({"error": str(error)}), 400

    was_archived = file.archived_at is not None
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
    if was_archived and file.archived_at is None:
        file_ops.unarchive_file(file)
    promote_legacy_embeds(file)
    # Pointers removed from the file body must drop the object rows too
    # (selection Backspace/Cut in the editor often only PATCHes the document).
    if document_changed:
        purge_unreferenced_embeds_for_file(file)
    db.session.commit()
    return jsonify(file.to_dict())


@files_bp.route("/files/<int:file_id>", methods=["DELETE"])
def delete_file(file_id):
    get_or_404(File, file_id)
    delete_file_cascade(file_id)
    db.session.commit()
    return "", 204
