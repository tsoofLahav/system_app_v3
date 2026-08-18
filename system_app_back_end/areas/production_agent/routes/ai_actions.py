"""Saved AI actions: a prompt on a button, on the bar or in the actions menu.

Nothing here schedules anything. An action runs when the user presses it, on
whatever they have open — the client sends live `scope` and `hints`, exactly
like a typed prompt.
"""

from flask import Blueprint, jsonify, request

from models import AiAction, db
from shared.bootstrap import default_workspace_id
from shared.helpers import apply_updates, get_or_404
from shared.run_config import DEFAULT_MANUAL_APPLY_MODE
from areas.production_agent.services.action_bar import (
    slots_after_claim,
    slots_from_order,
)
from areas.production_agent.services.runner import run_agent

ai_actions_bp = Blueprint("ai_actions", __name__)


def _pinned_slots(workspace_id: int) -> dict[int, int]:
    rows = AiAction.query.filter(
        AiAction.workspace_id == workspace_id,
        AiAction.bar_slot.isnot(None),
    ).all()
    return {row.id: row.bar_slot for row in rows}


def _write_slots(workspace_id: int, slots: dict[int, int]) -> None:
    """Push a whole `{id: slot}` map onto the workspace's actions.

    Slots are cleared in their own flush first: the unique index is checked per
    statement, so handing slot 3 from one action to another has to empty it
    before filling it again.
    """
    rows = AiAction.query.filter_by(workspace_id=workspace_id).all()
    moved = [row for row in rows if row.bar_slot != slots.get(row.id)]
    for row in moved:
        row.bar_slot = None
    db.session.flush()
    for row in moved:
        row.bar_slot = slots.get(row.id)
    db.session.flush()


@ai_actions_bp.route("/ai-actions", methods=["GET"])
def list_ai_actions():
    workspace_id = request.args.get("workspace_id", type=int) or default_workspace_id()
    query = AiAction.query
    if workspace_id:
        query = query.filter_by(workspace_id=workspace_id)
    rows = query.order_by(AiAction.id).all()
    return jsonify([r.to_dict() for r in rows])


@ai_actions_bp.route("/ai-actions/bar-order", methods=["PUT"])
def reorder_ai_action_bar():
    """Set the AI bar: `ordered_ids` take slots 1..6, everything else unpins."""
    data = request.get_json(silent=True) or {}
    workspace_id = data.get("workspace_id") or default_workspace_id()
    if not workspace_id:
        return jsonify({"error": "workspace_id is required"}), 400
    try:
        slots = slots_from_order(data.get("ordered_ids") or [])
    except (TypeError, ValueError) as error:
        return jsonify({"error": str(error)}), 400

    owned = {row.id for row in AiAction.query.filter_by(workspace_id=workspace_id).all()}
    if not set(slots).issubset(owned):
        return jsonify({"error": "action ids must belong to the workspace"}), 400

    _write_slots(workspace_id, slots)
    db.session.commit()
    rows = (
        AiAction.query.filter_by(workspace_id=workspace_id).order_by(AiAction.id).all()
    )
    return jsonify([r.to_dict() for r in rows])


@ai_actions_bp.route("/ai-actions", methods=["POST"])
def create_ai_action():
    data = request.get_json(silent=True) or {}
    if not data.get("name"):
        return jsonify({"error": "name is required"}), 400
    workspace_id = data.get("workspace_id") or default_workspace_id()
    if not workspace_id:
        return jsonify({"error": "workspace_id is required"}), 400
    row = AiAction(
        workspace_id=workspace_id,
        name=data["name"],
        prompt=data.get("prompt") or "",
        apply_mode=data.get("apply_mode") or DEFAULT_MANUAL_APPLY_MODE,
        icon=data.get("icon") or "",
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


@ai_actions_bp.route("/ai-actions/<int:action_id>", methods=["PATCH"])
def update_ai_action(action_id):
    row = get_or_404(AiAction, action_id)
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

    apply_updates(row, data, {"name", "prompt", "apply_mode", "icon"})
    db.session.commit()
    return jsonify(row.to_dict())


@ai_actions_bp.route("/ai-actions/<int:action_id>", methods=["DELETE"])
def delete_ai_action(action_id):
    row = get_or_404(AiAction, action_id)
    db.session.delete(row)
    db.session.commit()
    return "", 204


@ai_actions_bp.route("/ai-actions/<int:action_id>/run", methods=["POST"])
def run_ai_action(action_id):
    action = get_or_404(AiAction, action_id)
    data = request.get_json(silent=True) or {}
    result = run_agent(
        prompt=action.prompt,
        workspace_id=action.workspace_id,
        scope=data.get("scope") or {},
        apply_mode=action.apply_mode,
        hints=data.get("hints") or {},
    )
    return jsonify(result)
