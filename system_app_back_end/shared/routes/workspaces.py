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
    if not data.get("name"):
        return jsonify({"error": "name is required"}), 400
    workspace = Workspace(name=data["name"])
    db.session.add(workspace)
    db.session.commit()
    return jsonify(workspace.to_dict()), 201


@workspaces_bp.route("/workspaces/<int:workspace_id>", methods=["DELETE"])
def delete_workspace(workspace_id):
    get_or_404(Workspace, workspace_id)
    delete_workspace_cascade(workspace_id)
    db.session.commit()
    return "", 204
