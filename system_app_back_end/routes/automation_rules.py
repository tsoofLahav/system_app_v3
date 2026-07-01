from datetime import datetime

from flask import Blueprint, current_app, jsonify, request
from sqlalchemy.exc import OperationalError, ProgrammingError

from models import AutomationRule, db
from routes.helpers import apply_updates, get_or_404, parse_datetime

from services.automation_definitions import (
    allowed_trigger_types,
    default_create_payload,
    get_definition,
    validate_rule_update,
)
from services.automation_params import finalize_rule_params
from services.automation_schedule import DEFAULT_AUTOMATION_TIMEZONE, next_run_after

automation_rules_bp = Blueprint("automation_rules", __name__)


def _merge_rule_params(existing, incoming):
    base = dict(existing or {})
    merged = {**base, **incoming}
    if isinstance(incoming.get("trigger"), dict):
        trigger = dict(base.get("trigger") or {})
        trigger.update(incoming["trigger"])
        merged["trigger"] = trigger
    if isinstance(incoming.get("companion_task"), dict):
        companion = dict(base.get("companion_task") or {})
        companion.update(incoming["companion_task"])
        merged["companion_task"] = companion
    return merged


def _default_next_run(schedule, timezone=DEFAULT_AUTOMATION_TIMEZONE):
    if not schedule:
        return None
    try:
        return next_run_after(schedule, datetime.utcnow(), timezone=timezone)
    except Exception:
        return None


@automation_rules_bp.route("/automation_rules", methods=["GET"])
def list_automation_rules():
    rules = AutomationRule.query.order_by(AutomationRule.id).all()
    payload = []
    for rule in rules:
        item = rule.to_dict()
        definition = get_definition(rule.key, rule.action_type)
        if definition is not None:
            item["definition"] = definition.to_dict()
        payload.append(item)
    return jsonify(payload)


@automation_rules_bp.route("/automation_rules/<int:rule_id>", methods=["GET"])
def get_automation_rule(rule_id):
    rule = get_or_404(AutomationRule, rule_id)
    item = rule.to_dict()
    definition = get_definition(rule.key, rule.action_type)
    if definition is not None:
        item["definition"] = definition.to_dict()
    return jsonify(item)


@automation_rules_bp.route("/automation_rules", methods=["POST"])
def create_automation_rule():
    data = request.get_json(silent=True) or {}
    rule_key = data.get("key")
    builtin = default_create_payload(rule_key) if rule_key else None
    if builtin is not None:
        for field, value in builtin.items():
            data.setdefault(field, value)

    trigger_type = data.get("trigger_type", "schedule")
    required = {"key", "name", "action_type"}
    if any(not data.get(field) for field in required):
        return jsonify({"error": "key, name, and action_type are required"}), 400

    definition = get_definition(data["key"], data.get("action_type"))
    if definition is not None:
        if trigger_type not in allowed_trigger_types(data["key"], data["action_type"]):
            return jsonify({
                "error": f"trigger_type '{trigger_type}' is not allowed for {data['key']}",
            }), 400
        params = data.get("params") or {}
        if "scope" in params or "bindings" in params:
            return jsonify({
                "error": "params.scope and params.bindings are fixed for built-in automations",
            }), 400

    if trigger_type == "schedule" and not data.get("schedule"):
        return jsonify({"error": "schedule is required for schedule rules"}), 400
    if trigger_type == "task":
        trigger = (data.get("params") or {}).get("trigger") or {}
        if not trigger.get("view_type"):
            return jsonify({"error": "params.trigger.view_type is required for task rules"}), 400

    schedule = data.get("schedule")
    next_run_at = data.get("next_run_at")
    rule = AutomationRule(
        key=data["key"],
        name=data["name"],
        action_type=data["action_type"],
        trigger_type=trigger_type,
        schedule=schedule,
        timezone=data.get("timezone", DEFAULT_AUTOMATION_TIMEZONE),
        params=data.get("params", {}),
        enabled=data.get("enabled", True),
        last_run_at=parse_datetime(data.get("last_run_at")) if data.get("last_run_at") else None,
        next_run_at=parse_datetime(next_run_at)
        if next_run_at
        else _default_next_run(schedule, data.get("timezone", DEFAULT_AUTOMATION_TIMEZONE)),
    )
    finalize_rule_params(rule)
    db.session.add(rule)
    db.session.flush()
    if rule.trigger_type == "task" and rule.enabled:
        from services.automation_trigger import ensure_trigger_task

        ensure_trigger_task(rule)
    db.session.commit()
    return jsonify(rule.to_dict()), 201


@automation_rules_bp.route("/automation_rules/<int:rule_id>", methods=["PATCH"])
def update_automation_rule(rule_id):
    rule = get_or_404(AutomationRule, rule_id)
    data = request.get_json(silent=True) or {}
    previous_trigger_type = rule.trigger_type
    previous_enabled = rule.enabled

    validation_error = validate_rule_update(rule, data)
    if validation_error:
        return jsonify({"error": validation_error}), 400

    if "params" in data and isinstance(data["params"], dict):
        incoming = dict(data["params"])
        incoming.pop("scope", None)
        incoming.pop("bindings", None)
        data["params"] = _merge_rule_params(rule.params, incoming)

    apply_updates(
        rule,
        data,
        {
            "key",
            "name",
            "action_type",
            "trigger_type",
            "schedule",
            "timezone",
            "params",
            "enabled",
            "last_run_at",
            "next_run_at",
        },
        datetime_fields={"last_run_at", "next_run_at"},
    )
    finalize_rule_params(rule)
    if ("schedule" in data or "timezone" in data) and "next_run_at" not in data:
        rule.next_run_at = _default_next_run(rule.schedule, rule.timezone)

    from services.automation_trigger import ensure_trigger_task, hide_trigger_task

    was_task = previous_trigger_type == "task"
    is_task = rule.trigger_type == "task"
    if is_task and rule.enabled:
        ensure_trigger_task(rule)
    elif was_task and (not is_task or not rule.enabled):
        hide_trigger_task(rule)

    db.session.commit()
    return jsonify(rule.to_dict())


@automation_rules_bp.route("/automation_rules/<int:rule_id>/run", methods=["POST"])
def run_automation_rule_now(rule_id):
    rule = get_or_404(AutomationRule, rule_id)
    from services.automation_dispatcher import dispatch_manual_rule
    from services.automation_runner import kick_run_async

    try:
        run_ids = dispatch_manual_rule(rule)
    except (ProgrammingError, OperationalError) as error:
        db.session.rollback()
        detail = str(error.orig) if getattr(error, "orig", None) else str(error)
        return jsonify({
            "error": (
                "Automation queue schema is missing. "
                "Apply migrations/007_automation_run_queue.sql on this database."
            ),
            "detail": detail,
        }), 503

    if not run_ids:
        return jsonify({"error": "automation is already running"}), 409

    app = current_app._get_current_object()
    runs = []
    for run_id in run_ids:
        kick_run_async(app, run_id)
        from models import AutomationRun

        run = db.session.get(AutomationRun, run_id)
        if run is not None:
            runs.append(run.to_dict())

    primary = runs[0] if runs else {"id": run_ids[0], "status": "queued"}
    return jsonify({"run": primary, "runs": runs}), 202


@automation_rules_bp.route("/automation_rules/<int:rule_id>", methods=["DELETE"])
def delete_automation_rule(rule_id):
    rule = get_or_404(AutomationRule, rule_id)
    db.session.delete(rule)
    db.session.commit()
    return "", 204
