from flask import Blueprint, jsonify, request

from models import Workspace, db
from shared.helpers import get_or_404
from areas.objects.services.delete_cascade import delete_workspace_cascade

workspaces_bp = Blueprint("workspaces", __name__)


@workspaces_bp.route("/workspaces", methods=["GET"])
def list_workspaces():
    workspaces = Workspace.query.order_by(Workspace.id).all()
    return jsonify([w.to_dict() for w in workspaces])


@workspaces_bp.route("/workspaces/<int:workspace_id>", methods=["GET"])
def get_workspace(workspace_id):
    return jsonify(get_or_404(Workspace, workspace_id).to_dict())


@workspaces_bp.route("/workspaces", methods=["POST"])
def create_workspace():
    data = request.get_json(silent=True) or {}
    name = str(data.get("name") or "").strip()
    if not name:
        return jsonify({"error": "name is required"}), 400
    workspace = Workspace(name=name)
    db.session.add(workspace)
    db.session.flush()
    from models import Topic, File
    from areas.files.services.document_v3 import empty_document_json
    from areas.production_agent.services.prompt import ensure_agent_config
    home = Topic(workspace_id=workspace.id, name="Home", icon="🏠", color="#6366F1", order_index=0)
    db.session.add(home)
    db.session.flush()
    db.session.add(File(topic_id=home.id, name="Daily", document_json=empty_document_json(), order_index=0, meta={"automation_anchor": "daily"}))
    ensure_agent_config(workspace.id)
    db.session.commit()
    return jsonify(workspace.to_dict()), 201


@workspaces_bp.route("/workspaces/<int:workspace_id>", methods=["DELETE"])
def delete_workspace(workspace_id):
    get_or_404(Workspace, workspace_id)
    delete_workspace_cascade(workspace_id)
    db.session.commit()
    return "", 204
