from flask import Blueprint, jsonify

from shared.bootstrap import bootstrap_if_empty

bootstrap_bp = Blueprint("bootstrap", __name__)


@bootstrap_bp.route("/bootstrap", methods=["POST"])
def bootstrap():
    return jsonify(bootstrap_if_empty())


@bootstrap_bp.route("/bootstrap/status", methods=["GET"])
def bootstrap_status():
    from shared.bootstrap import default_workspace_id

    workspace_id = default_workspace_id()
    return jsonify({"ready": workspace_id is not None, "workspace_id": workspace_id})
