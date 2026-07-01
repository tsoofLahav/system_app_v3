from flask import Blueprint, jsonify, request

from models import AutomationCompanionTask, db
from routes.helpers import get_or_404
from services.automation_companion import (
    complete_companion_task,
    enrich_companion_dict,
    pending_companions_for_task,
)

automation_companion_bp = Blueprint("automation_companion", __name__)


@automation_companion_bp.route("/automation_companion_tasks", methods=["GET"])
def list_automation_companion_tasks():
    status = request.args.get("status", "pending")
    query = AutomationCompanionTask.query.order_by(AutomationCompanionTask.id.desc())
    if status:
        statuses = [value.strip() for value in status.split(",") if value.strip()]
        if statuses:
            query = query.filter(AutomationCompanionTask.status.in_(statuses))
    links = query.limit(100).all()
    return jsonify([enrich_companion_dict(link) for link in links])


@automation_companion_bp.route(
    "/automation_companion_tasks/<int:companion_id>/complete", methods=["POST"]
)
def complete_automation_companion_task(companion_id):
    link = get_or_404(AutomationCompanionTask, companion_id)
    result = complete_companion_task(link.id)
    db.session.commit()
    return jsonify(result)


@automation_companion_bp.route(
    "/automation_companion_tasks/by-task/<int:task_id>", methods=["GET"]
)
def get_automation_companion_by_task(task_id):
    links = pending_companions_for_task(task_id)
    if not links:
        return jsonify({"error": "companion task not found"}), 404
    return jsonify(links[0])


@automation_companion_bp.route(
    "/automation_companion_tasks/by-task/<int:task_id>/pending", methods=["GET"]
)
def list_pending_companions_for_task(task_id):
    return jsonify(pending_companions_for_task(task_id))
