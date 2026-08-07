from flask import Blueprint, jsonify, request

from areas.production_agent.services.runner import run_agent
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
