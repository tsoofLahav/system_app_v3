from datetime import datetime

from flask import Blueprint, jsonify, request

from models import Automation, AutomationRun, db
from shared.helpers import apply_updates, get_or_404
from areas.production_agent.services.runner import run_agent
from shared.bootstrap import default_workspace_id
from shared.run_config import DEFAULT_AUTOMATION_APPLY_MODE
from areas.objects.services.delete_cascade import delete_automation_cascade

automations_bp = Blueprint("automations", __name__)


@automations_bp.route("/automations", methods=["GET"])
def list_automations():
    workspace_id = request.args.get("workspace_id", type=int) or default_workspace_id()
    query = Automation.query
    if workspace_id:
        query = query.filter_by(workspace_id=workspace_id)
    rows = query.order_by(Automation.id).all()
    return jsonify([r.to_dict() for r in rows])


@automations_bp.route("/automations", methods=["POST"])
def create_automation():
    data = request.get_json(silent=True) or {}
    if not data.get("name"):
        return jsonify({"error": "name is required"}), 400
    workspace_id = data.get("workspace_id") or default_workspace_id()
    if not workspace_id:
        return jsonify({"error": "workspace_id is required"}), 400
    row = Automation(
        workspace_id=workspace_id,
        name=data["name"],
        trigger=data.get("trigger") or {},
        scope=data.get("scope") or {},
        prompt=data.get("prompt") or "",
        apply_mode=data.get("apply_mode") or DEFAULT_AUTOMATION_APPLY_MODE,
        schedule=data.get("schedule"),
        timezone=data.get("timezone", "UTC"),
        enabled=bool(data.get("enabled", True)),
    )
    db.session.add(row)
    db.session.commit()
    return jsonify(row.to_dict()), 201


@automations_bp.route("/automations/<int:automation_id>", methods=["PATCH"])
def update_automation(automation_id):
    row = get_or_404(Automation, automation_id)
    data = request.get_json(silent=True) or {}
    apply_updates(
        row,
        data,
        {
            "name",
            "trigger",
            "scope",
            "prompt",
            "apply_mode",
            "schedule",
            "timezone",
            "enabled",
            "last_run_at",
            "next_run_at",
        },
        datetime_fields={"last_run_at", "next_run_at"},
    )
    db.session.commit()
    return jsonify(row.to_dict())


@automations_bp.route("/automations/<int:automation_id>", methods=["DELETE"])
def delete_automation(automation_id):
    get_or_404(Automation, automation_id)
    delete_automation_cascade(automation_id)
    db.session.commit()
    return "", 204


@automations_bp.route("/automations/<int:automation_id>/run", methods=["POST"])
def run_automation(automation_id):
    automation = get_or_404(Automation, automation_id)
    run = AutomationRun(
        automation_id=automation.id,
        status="running",
        trigger_source="manual",
    )
    db.session.add(run)
    db.session.flush()

    try:
        result = run_agent(
            prompt=automation.prompt,
            workspace_id=automation.workspace_id,
            scope=automation.scope or {},
            apply_mode=automation.apply_mode,
        )
        run.status = "completed" if result.get("status") == "ok" else "failed"
        run.result = result
        run.finished_at = datetime.utcnow()
        automation.last_run_at = run.finished_at
        if result.get("status") != "ok":
            run.error = result.get("error")
    except Exception as error:
        run.status = "failed"
        run.error = str(error)
        run.finished_at = datetime.utcnow()
        result = {"status": "error", "error": str(error)}

    db.session.commit()
    return jsonify({"run": run.to_dict(), "agent": result})
