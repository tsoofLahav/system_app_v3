from flask import Blueprint, jsonify, request

from models import AutomationRun
from routes.helpers import get_or_404

automation_runs_bp = Blueprint("automation_runs", __name__)


@automation_runs_bp.route("/automation_runs", methods=["GET"])
def list_automation_runs():
    status_param = request.args.get("status", "")
    rule_id = request.args.get("rule_id", type=int)
    limit = request.args.get("limit", 20, type=int)
    limit = max(1, min(limit, 100))

    query = AutomationRun.query.order_by(AutomationRun.id.desc())
    if status_param:
        statuses = [value.strip() for value in status_param.split(",") if value.strip()]
        if statuses:
            query = query.filter(AutomationRun.status.in_(statuses))
    if rule_id is not None:
        query = query.filter_by(rule_id=rule_id)

    runs = query.limit(limit).all()
    return jsonify([run.to_dict() for run in runs])


@automation_runs_bp.route("/automation_runs/<int:run_id>", methods=["GET"])
def get_automation_run(run_id):
    return jsonify(get_or_404(AutomationRun, run_id).to_dict())
