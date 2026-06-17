from datetime import datetime

from flask import Blueprint, jsonify, request

from models import AutomationRule, db
from routes.helpers import apply_updates, get_or_404, parse_datetime

automation_rules_bp = Blueprint("automation_rules", __name__)


def _default_next_run(schedule):
    try:
        from services.automation_runner import next_run_after

        return next_run_after(schedule, datetime.utcnow())
    except Exception:
        return None


@automation_rules_bp.route("/automation_rules", methods=["GET"])
def list_automation_rules():
    rules = AutomationRule.query.order_by(AutomationRule.id).all()
    return jsonify([r.to_dict() for r in rules])


@automation_rules_bp.route("/automation_rules/<int:rule_id>", methods=["GET"])
def get_automation_rule(rule_id):
    return jsonify(get_or_404(AutomationRule, rule_id).to_dict())


@automation_rules_bp.route("/automation_rules", methods=["POST"])
def create_automation_rule():
    data = request.get_json(silent=True) or {}
    required = {"key", "name", "action_type", "schedule"}
    if any(not data.get(field) for field in required):
        return jsonify({"error": "key, name, action_type, and schedule are required"}), 400

    next_run_at = data.get("next_run_at")
    rule = AutomationRule(
        key=data["key"],
        name=data["name"],
        action_type=data["action_type"],
        trigger_type=data.get("trigger_type", "schedule"),
        schedule=data["schedule"],
        timezone=data.get("timezone", "UTC"),
        params=data.get("params", {}),
        enabled=data.get("enabled", True),
        last_run_at=parse_datetime(data.get("last_run_at")) if data.get("last_run_at") else None,
        next_run_at=parse_datetime(next_run_at) if next_run_at else _default_next_run(data["schedule"]),
    )
    db.session.add(rule)
    db.session.commit()
    return jsonify(rule.to_dict()), 201


@automation_rules_bp.route("/automation_rules/<int:rule_id>", methods=["PATCH"])
def update_automation_rule(rule_id):
    rule = get_or_404(AutomationRule, rule_id)
    data = request.get_json(silent=True) or {}
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
    if "schedule" in data and "next_run_at" not in data:
        rule.next_run_at = _default_next_run(rule.schedule)
    db.session.commit()
    return jsonify(rule.to_dict())


@automation_rules_bp.route("/automation_rules/<int:rule_id>/run", methods=["POST"])
def run_automation_rule_now(rule_id):
    rule = get_or_404(AutomationRule, rule_id)
    from services.automation_runner import run_rule

    return jsonify(run_rule(rule, now=datetime.utcnow()))


@automation_rules_bp.route("/automation_rules/<int:rule_id>", methods=["DELETE"])
def delete_automation_rule(rule_id):
    rule = get_or_404(AutomationRule, rule_id)
    db.session.delete(rule)
    db.session.commit()
    return "", 204
