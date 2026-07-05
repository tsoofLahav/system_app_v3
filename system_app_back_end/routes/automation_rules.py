from datetime import datetime

from flask import Blueprint, current_app, jsonify, request
from sqlalchemy.exc import OperationalError, ProgrammingError

from models import AutomationRule, db
from routes.helpers import apply_updates, get_or_404, parse_datetime

from services.automation_definitions import (
    default_create_payload,
    get_definition,
    validate_rule_update,
)
from services.automation_params import finalize_rule_params, merge_rule_params, normalize_params
from services.automation_schedule import DEFAULT_AUTOMATION_TIMEZONE, next_run_after
from services.view_task_reset_schedule import next_view_reset_run

automation_rules_bp = Blueprint("automation_rules", __name__)


def _rule_payload(rule):
    item = rule.to_dict()
    item["params"] = normalize_params(rule.params, rule.key, rule.action_type)
    definition = get_definition(rule.key, rule.action_type)
    if definition is not None:
        item["definition"] = definition.to_dict()
    return item


def _default_next_run(schedule, timezone=DEFAULT_AUTOMATION_TIMEZONE):
    if not schedule:
        return None


def _default_next_run_for_rule(rule):
    if rule.key == "view_task_reset" and rule.action_type == "reset_view_tasks":
        try:
            return next_view_reset_run(rule.params or {}, datetime.utcnow(), rule.timezone)
        except Exception:
            return None
    return _default_next_run(rule.schedule, rule.timezone)
    try:
        return next_run_after(schedule, datetime.utcnow(), timezone=timezone)
    except Exception:
        return None


@automation_rules_bp.route("/automation_rules", methods=["GET"])
def list_automation_rules():
    rules = AutomationRule.query.order_by(AutomationRule.id).all()
    return jsonify([_rule_payload(rule) for rule in rules])


@automation_rules_bp.route("/automation_rules/<int:rule_id>", methods=["GET"])
def get_automation_rule(rule_id):
    rule = get_or_404(AutomationRule, rule_id)
    return jsonify(_rule_payload(rule))


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
        next_run_at=parse_datetime(next_run_at) if next_run_at else None,
    )
    finalize_rule_params(rule)
    if next_run_at is None:
        rule.next_run_at = _default_next_run_for_rule(rule)
    db.session.add(rule)
    db.session.flush()
    if rule.trigger_type == "task" and rule.enabled:
        from services.automation_trigger import ensure_trigger_task

        ensure_trigger_task(rule)
    db.session.commit()
    return jsonify(_rule_payload(rule)), 201


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
        existing = normalize_params(rule.params, rule.key, rule.action_type)
        data["params"] = merge_rule_params(existing, data["params"])

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
    if (
        "next_run_at" not in data
        and {"schedule", "timezone", "params", "enabled"}.intersection(data)
    ):
        rule.next_run_at = _default_next_run_for_rule(rule) if rule.enabled else None

    from services.automation_trigger import ensure_trigger_task, hide_trigger_task

    was_task = previous_trigger_type == "task"
    is_task = rule.trigger_type == "task"
    if is_task and rule.enabled:
        ensure_trigger_task(rule)
    elif was_task and (not is_task or not rule.enabled):
        hide_trigger_task(rule)

    db.session.commit()
    return jsonify(_rule_payload(rule))


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
