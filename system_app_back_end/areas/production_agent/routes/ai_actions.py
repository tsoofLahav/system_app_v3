"""Saved AI actions: a prompt on a button, on the bar or in the actions menu.

Nothing here schedules anything. An action runs when the user presses it, on
whatever they have open — the client sends live `scope` and `hints`, exactly
like a typed prompt.
"""

from flask import Blueprint, jsonify, request

from models import AiAction, Topic, TopicType, db
from shared.bootstrap import default_workspace_id
from shared.helpers import apply_updates, get_or_404
from shared.run_config import DEFAULT_MANUAL_APPLY_MODE
from areas.production_agent.services.action_bar import (
    AI_TOPIC_ACTIONS_PER_TOPIC,
    first_free_topic_extra,
    is_topic_extra_slot,
    slots_after_claim,
    slots_from_order,
    topic_extra_after_claim,
)
from areas.production_agent.services.runner import run_agent

ai_actions_bp = Blueprint("ai_actions", __name__)


def _clean_name(value) -> str:
    return str(value or "").strip()


def _topic_in_workspace(topic_id, workspace_id: int) -> Topic | None:
    if topic_id in (None, ""):
        return None
    row = db.session.get(Topic, int(topic_id))
    if row is None or int(row.workspace_id) != int(workspace_id):
        return None
    return row


def _apply_scope(row: AiAction, data: dict, workspace_id: int) -> str | None:
    """topic_id xor topic_type_id xor neither (all). Topic wins if both sent."""
    has_topic = "topic_id" in data
    has_type = "topic_type_id" in data
    if not has_topic and not has_type:
        return None
    topic_raw = data.get("topic_id") if has_topic else None
    type_raw = data.get("topic_type_id") if has_type else None
    if has_topic and topic_raw not in (None, ""):
        topic = _topic_in_workspace(topic_raw, workspace_id)
        if topic is None:
            return "topic not found"
        row.topic_id = topic.id
        row.topic_type_id = None
        return None
    if has_type and type_raw not in (None, ""):
        type_row = _topic_type_in_workspace(type_raw, workspace_id)
        if type_row is None:
            return "topic type not found"
        row.topic_type_id = type_row.id
        row.topic_id = None
        return None
    row.topic_id = None
    row.topic_type_id = None
    return None


def _topic_type_in_workspace(type_id, workspace_id: int) -> TopicType | None:
    if type_id in (None, ""):
        return None
    row = db.session.get(TopicType, int(type_id))
    if row is None or int(row.workspace_id) != int(workspace_id):
        return None
    return row


def _fixed_pinned_slots(workspace_id: int) -> dict[int, int]:
    rows = AiAction.query.filter(
        AiAction.workspace_id == workspace_id,
        AiAction.topic_id.is_(None),
        AiAction.bar_slot.isnot(None),
    ).all()
    return {row.id: row.bar_slot for row in rows}


def _topic_extra_slots(workspace_id: int, topic_id: int) -> dict[int, int]:
    rows = AiAction.query.filter(
        AiAction.workspace_id == workspace_id,
        AiAction.topic_id == topic_id,
        AiAction.bar_slot.isnot(None),
    ).all()
    return {row.id: row.bar_slot for row in rows}


def _topic_action_count(
    workspace_id: int, topic_id: int, exclude_id: int | None = None
) -> int:
    query = AiAction.query.filter_by(workspace_id=workspace_id, topic_id=topic_id)
    if exclude_id is not None:
        query = query.filter(AiAction.id != exclude_id)
    return query.count()


def _write_slot_map(rows: list[AiAction], slots: dict[int, int]) -> None:
    """Push `{id: slot}` onto [rows]. Clear first so the unique index can swap."""
    moved = [row for row in rows if row.bar_slot != slots.get(row.id)]
    for row in moved:
        row.bar_slot = None
    db.session.flush()
    for row in moved:
        row.bar_slot = slots.get(row.id)
    db.session.flush()


def _write_fixed_slots(workspace_id: int, slots: dict[int, int]) -> None:
    rows = AiAction.query.filter(
        AiAction.workspace_id == workspace_id,
        AiAction.topic_id.is_(None),
    ).all()
    _write_slot_map(rows, slots)


def _write_topic_extra_slots(
    workspace_id: int, topic_id: int, slots: dict[int, int]
) -> None:
    rows = AiAction.query.filter_by(workspace_id=workspace_id, topic_id=topic_id).all()
    _write_slot_map(rows, slots)


def _clear_bar_slot(row: AiAction) -> None:
    if row.bar_slot is None:
        return
    row.bar_slot = None
    db.session.flush()


def _seat_topic_extra(row: AiAction, slot="auto") -> str | None:
    """Put a topic-scoped action on extra 9/10. `unpin` clears the extra seat."""
    extras = _topic_extra_slots(row.workspace_id, row.topic_id)
    if slot == "unpin":
        target = None
    elif slot == "auto":
        target = extras.get(row.id) or first_free_topic_extra(extras)
        if target is None:
            return "this topic already has 2 specific actions"
    else:
        target = slot
    try:
        next_slots = topic_extra_after_claim(extras, row.id, target)
    except (TypeError, ValueError) as error:
        return str(error)
    _write_topic_extra_slots(row.workspace_id, row.topic_id, next_slots)
    return None


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
    """Set the fixed AI bar: `ordered_ids` take slots 1..7. Topic extras stay."""
    data = request.get_json(silent=True) or {}
    workspace_id = data.get("workspace_id") or default_workspace_id()
    if not workspace_id:
        return jsonify({"error": "workspace_id is required"}), 400
    rows = AiAction.query.filter_by(workspace_id=workspace_id).all()
    owned_fixed = {row.id for row in rows if row.topic_id is None}
    ordered = [
        int(i) for i in (data.get("ordered_ids") or []) if int(i) in owned_fixed
    ]
    try:
        slots = slots_from_order(ordered)
    except (TypeError, ValueError) as error:
        return jsonify({"error": str(error)}), 400

    _write_fixed_slots(workspace_id, slots)
    db.session.commit()
    rows = (
        AiAction.query.filter_by(workspace_id=workspace_id).order_by(AiAction.id).all()
    )
    return jsonify([r.to_dict() for r in rows])


@ai_actions_bp.route("/ai-actions", methods=["POST"])
def create_ai_action():
    data = request.get_json(silent=True) or {}
    name = _clean_name(data.get("name"))
    name_he = _clean_name(data.get("name_he"))
    if not name or not name_he:
        return jsonify({"error": "name and name_he are required"}), 400
    workspace_id = data.get("workspace_id") or default_workspace_id()
    if not workspace_id:
        return jsonify({"error": "workspace_id is required"}), 400
    row = AiAction(
        workspace_id=workspace_id,
        name=name,
        name_he=name_he,
        prompt=data.get("prompt") or "",
        apply_mode=data.get("apply_mode") or DEFAULT_MANUAL_APPLY_MODE,
        icon=data.get("icon") or "",
        requires_user_input=bool(data.get("requires_user_input", False)),
        user_input_prompt=data.get("user_input_prompt") or "",
    )
    scope_error = _apply_scope(row, data, workspace_id)
    if scope_error:
        return jsonify({"error": scope_error}), 400
    if row.topic_id is not None:
        if (
            _topic_action_count(workspace_id, row.topic_id)
            >= AI_TOPIC_ACTIONS_PER_TOPIC
        ):
            return jsonify({"error": "this topic already has 2 specific actions"}), 400
    db.session.add(row)
    db.session.flush()

    if row.topic_id is not None:
        extra_error = _seat_topic_extra(row)
        if extra_error:
            db.session.rollback()
            return jsonify({"error": extra_error}), 400
    elif data.get("bar_slot") is not None:
        try:
            slots = slots_after_claim(
                _fixed_pinned_slots(workspace_id), row.id, data["bar_slot"]
            )
        except (TypeError, ValueError) as error:
            db.session.rollback()
            return jsonify({"error": str(error)}), 400
        _write_fixed_slots(workspace_id, slots)

    db.session.commit()
    return jsonify(row.to_dict()), 201


@ai_actions_bp.route("/ai-actions/<int:action_id>", methods=["PATCH"])
def update_ai_action(action_id):
    row = get_or_404(AiAction, action_id)
    data = request.get_json(silent=True) or {}

    if "topic_id" in data or "topic_type_id" in data:
        will_be_topic = "topic_id" in data and data.get("topic_id") not in (None, "")
        was_topic = row.topic_id is not None
        same_topic = (
            was_topic
            and will_be_topic
            and int(data["topic_id"]) == row.topic_id
        )
        if will_be_topic and not same_topic:
            if (
                _topic_action_count(
                    row.workspace_id, int(data["topic_id"]), exclude_id=row.id
                )
                >= AI_TOPIC_ACTIONS_PER_TOPIC
            ):
                return jsonify(
                    {"error": "this topic already has 2 specific actions"}
                ), 400
        if was_topic != will_be_topic or (will_be_topic and not same_topic):
            _clear_bar_slot(row)
        scope_error = _apply_scope(row, data, row.workspace_id)
        if scope_error:
            return jsonify({"error": scope_error}), 400
        if will_be_topic and not same_topic:
            extra_error = _seat_topic_extra(row)
            if extra_error:
                return jsonify({"error": extra_error}), 400

    # Pinning goes through the slot rules, not a plain field write: taking a
    # slot has to free it on whoever held it.
    if "bar_slot" in data:
        if row.topic_id is not None:
            if data["bar_slot"] is None:
                extra_error = _seat_topic_extra(row, slot="unpin")
            elif is_topic_extra_slot(data["bar_slot"]):
                extra_error = _seat_topic_extra(row, slot=data["bar_slot"])
            else:
                extra_error = "topic extras use seats 9 and 10"
            if extra_error:
                return jsonify({"error": extra_error}), 400
        else:
            try:
                slots = slots_after_claim(
                    _fixed_pinned_slots(row.workspace_id), row.id, data["bar_slot"]
                )
            except (TypeError, ValueError) as error:
                return jsonify({"error": str(error)}), 400
            _write_fixed_slots(row.workspace_id, slots)

    if "name" in data or "name_he" in data:
        name = _clean_name(data["name"]) if "name" in data else (row.name or "")
        name_he = (
            _clean_name(data["name_he"]) if "name_he" in data else (row.name_he or "")
        )
        if not name or not name_he:
            return jsonify({"error": "name and name_he are required"}), 400
        row.name = name
        row.name_he = name_he

    apply_updates(
        row,
        data,
        {"prompt", "apply_mode", "icon", "requires_user_input", "user_input_prompt"},
    )
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
