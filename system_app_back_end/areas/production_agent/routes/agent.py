from flask import Blueprint, jsonify, request

from models import File, db
from shared.helpers import get_or_404
from areas.production_agent.services.runner import run_agent
from areas.production_agent.services.write_tools import (
    _object_updates_from_json,
    commit_agent_file_apply,
)
from areas.production_agent.services.pending_reviews import (
    discard_pending,
    finish_pending,
    get_pending_for_file,
)
from shared.run_config import DEFAULT_MANUAL_APPLY_MODE

agent_bp = Blueprint("agent", __name__)


@agent_bp.route("/agent/run", methods=["POST"])
def agent_run():
    data = request.get_json(silent=True) or {}
    prompt = data.get("prompt")
    workspace_id = data.get("workspace_id")
    if not prompt or not workspace_id:
        return jsonify({"error": "prompt and workspace_id are required"}), 400

    apply_mode = data.get("apply_mode") or DEFAULT_MANUAL_APPLY_MODE
    result = run_agent(
        prompt=prompt,
        workspace_id=int(workspace_id),
        scope=data.get("scope") or {},
        apply_mode=apply_mode,
        context=data.get("context") or {},
        hints=data.get("hints") or {},
    )
    status_code = 200 if result.get("status") == "ok" else 500
    return jsonify(result), status_code


@agent_bp.route("/files/<int:file_id>/apply-agent-text", methods=["POST"])
def apply_agent_text_route(file_id):
    """Accept a reviewed proposal: document_json + object_updates atomically."""
    file = get_or_404(File, file_id)
    data = request.get_json(silent=True) or {}
    new_body = data.get("document_json")
    if new_body is None:
        return jsonify({"error": "document_json is required"}), 400
    object_updates = _object_updates_from_json(data.get("object_updates"))
    errors = commit_agent_file_apply(
        file,
        new_document_json=str(new_body),
        object_updates=object_updates,
        source="agent",
    )
    if errors:
        db.session.rollback()
        return jsonify({"error": "; ".join(errors)}), 400
    db.session.commit()
    return jsonify(file.to_dict())


@agent_bp.route("/files/<int:file_id>/pending-review", methods=["GET"])
def get_pending_review(file_id):
    get_or_404(File, file_id)
    pending = get_pending_for_file(file_id)
    return jsonify({"pending": pending})


@agent_bp.route("/files/<int:file_id>/pending-review", methods=["DELETE"])
def delete_pending_review(file_id):
    get_or_404(File, file_id)
    if not discard_pending(file_id):
        return jsonify({"error": "no pending review"}), 404
    db.session.commit()
    return jsonify({"ok": True})


@agent_bp.route("/files/<int:file_id>/pending-review/finish", methods=["POST"])
def finish_pending_review(file_id):
    get_or_404(File, file_id)
    data = request.get_json(silent=True) or {}
    decisions = data.get("decisions")
    if not isinstance(decisions, list):
        return jsonify({"error": "decisions array required"}), 400
    result = finish_pending(
        file_id,
        decisions=decisions,
        archive_name=data.get("archive_name"),
    )
    if result.get("error"):
        db.session.rollback()
        return jsonify(result), 400
    db.session.commit()
    return jsonify(result)
