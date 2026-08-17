from datetime import datetime

from flask import Blueprint, jsonify, request

from models import Automation, AutomationRun, db
from shared.helpers import apply_updates, get_or_404
from areas.production_agent.services.runner import run_agent
from shared.bootstrap import default_workspace_id
from shared.run_config import DEFAULT_AUTOMATION_APPLY_MODE
from areas.objects.services.delete_cascade import delete_automation_cascade
from areas.automations.services.action_bar import (
    run_scope,
    slots_after_claim,
    slots_from_order,
)

automations_bp = Blueprint("automations", __name__)


def _pinned_slots(workspace_id: int) -> dict[int, int]:
    rows = Automation.query.filter(
        Automation.workspace_id == workspace_id,
        Automation.bar_slot.isnot(None),
    ).all()
    return {row.id: row.bar_slot for row in rows}


def _write_slots(workspace_id: int, slots: dict[int, int]) -> None:
    """Push a whole `{id: slot}` map onto the workspace's automations.

    Slots are cleared in their own flush first: the unique index is checked per
    statement, so handing slot 3 from one action to another has to empty it
    before filling it again.
    """
    rows = Automation.query.filter_by(workspace_id=workspace_id).all()
    moved = [row for row in rows if row.bar_slot != slots.get(row.id)]
    for row in moved:
        row.bar_slot = None
    db.session.flush()
    for row in moved:
        row.bar_slot = slots.get(row.id)
    db.session.flush()


@automations_bp.route("/automations", methods=["GET"])
def list_automations():
    workspace_id = request.args.get("workspace_id", type=int) or default_workspace_id()
    query = Automation.query
    if workspace_id:
        query = query.filter_by(workspace_id=workspace_id)
    rows = query.order_by(Automation.id).all()
    return jsonify([r.to_dict() for r in rows])


@automations_bp.route("/automations/bar-order", methods=["PUT"])
def reorder_automation_bar():
    """Set the AI bar: `ordered_ids` take slots 1..6, everything else unpins."""
    data = request.get_json(silent=True) or {}
    workspace_id = data.get("workspace_id") or default_workspace_id()
    if not workspace_id:
        return jsonify({"error": "workspace_id is required"}), 400
    try:
        slots = slots_from_order(data.get("ordered_ids") or [])
    except (TypeError, ValueError) as error:
        return jsonify({"error": str(error)}), 400

    owned = {
        row.id
        for row in Automation.query.filter_by(workspace_id=workspace_id).all()
    }
    if not set(slots).issubset(owned):
        return jsonify({"error": "automation ids must belong to the workspace"}), 400

    _write_slots(workspace_id, slots)
    db.session.commit()
    rows = (
        Automation.query.filter_by(workspace_id=workspace_id)
        .order_by(Automation.id)
        .all()
    )
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
        icon=data.get("icon") or "",
        schedule=data.get("schedule"),
        timezone=data.get("timezone", "UTC"),
        enabled=bool(data.get("enabled", True)),
    )
    db.session.add(row)
    db.session.flush()

    if data.get("bar_slot") is not None:
        try:
            slots = slots_after_claim(
                _pinned_slots(workspace_id), row.id, data["bar_slot"]
            )
        except (TypeError, ValueError) as error:
            db.session.rollback()
            return jsonify({"error": str(error)}), 400
        _write_slots(workspace_id, slots)

    db.session.commit()
    return jsonify(row.to_dict()), 201


@automations_bp.route("/automations/<int:automation_id>", methods=["PATCH"])
def update_automation(automation_id):
    row = get_or_404(Automation, automation_id)
    data = request.get_json(silent=True) or {}
    # Pinning goes through the slot rules, not a plain field write: taking a
    # slot has to free it on whoever held it.
    if "bar_slot" in data:
        try:
            slots = slots_after_claim(
                _pinned_slots(row.workspace_id), row.id, data["bar_slot"]
            )
        except (TypeError, ValueError) as error:
            return jsonify({"error": str(error)}), 400
        _write_slots(row.workspace_id, slots)

    apply_updates(
        row,
        data,
        {
            "name",
            "trigger",
            "scope",
            "prompt",
            "apply_mode",
            "icon",
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
    data = request.get_json(silent=True) or {}
    # Pressed from the AI bar, a saved action runs on what the user is looking
    # at, so the client sends live scope and hints. The scheduler sends neither
    # and falls back to the scope stored on the row.
    scope = run_scope(automation.scope, data.get("scope"))
    hints = data.get("hints") or {}
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
            scope=scope,
            apply_mode=automation.apply_mode,
            hints=hints,
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
