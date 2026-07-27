from flask import Blueprint, jsonify, request

from models import File, FileVersion, db
from shared.helpers import get_or_404
from areas.production_agent.services.runner import compute_diff

file_versions_bp = Blueprint("file_versions", __name__)


@file_versions_bp.route("/files/<int:file_id>/versions", methods=["GET"])
def list_versions(file_id):
    get_or_404(File, file_id)
    rows = (
        FileVersion.query.filter_by(file_id=file_id)
        .order_by(FileVersion.created_at.desc(), FileVersion.id.desc())
        .all()
    )
    return jsonify([r.to_dict() for r in rows])


@file_versions_bp.route("/files/<int:file_id>/diff", methods=["POST"])
def diff_file(file_id):
    get_or_404(File, file_id)
    data = request.get_json(silent=True) or {}
    old_body = data.get("old_body", "")
    new_body = data.get("new_body", "")
    return jsonify(compute_diff(old_body, new_body, file_id=file_id))
