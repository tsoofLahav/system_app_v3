"""Automations: a scope, a trigger, and an ordered series of steps.

Saved AI actions are a different thing and live at `/ai-actions`. They only
ever shared this table because both stored a prompt.
"""

from flask import Blueprint, jsonify, request

from models import Automation, db
from shared.bootstrap import default_workspace_id
from shared.helpers import apply_updates, get_or_404
from areas.objects.services.delete_cascade import delete_automation_cascade
from areas.automations.services.run_automation import run_automation
from areas.automations.services.steps import StepError, validate_steps

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
    try:
        steps = validate_steps(data.get("steps") or [])
    except StepError as error:
        return jsonify({"error": str(error)}), 400

    row = Automation(
        workspace_id=workspace_id,
        name=data["name"],
        trigger=data.get("trigger") or {},
        scope=data.get("scope") or {},
        steps=steps,
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
    if "steps" in data:
        try:
            data = {**data, "steps": validate_steps(data.get("steps") or [])}
        except StepError as error:
            return jsonify({"error": str(error)}), 400
    # A new clock means a new next fire — otherwise yesterday's 08:00 still
    # wins after the user moved it to 20:00.
    if "schedule" in data or "timezone" in data:
        data = {**data, "next_run_at": None}

    apply_updates(
        row,
        data,
        {
            "name",
            "trigger",
            "scope",
            "steps",
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
def run_automation_now(automation_id):
    """Run it this second, on its own stored scope — the same thing the clock
    would do, so testing an automation shows what it will really do."""
    automation = get_or_404(Automation, automation_id)
    run = run_automation(automation, trigger_source="manual")
    db.session.commit()
    return jsonify({"run": run.to_dict()})
