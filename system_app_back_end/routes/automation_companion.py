from flask import Blueprint, jsonify, request

from models import AutomationCompanionTask, Task, TaskView, Topic, db
from routes.helpers import get_or_404
from services.automation_companion import complete_companion_task

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
    return jsonify([link.to_dict() for link in links])


@automation_companion_bp.route(
    "/automation_companion_tasks/<int:companion_id>/complete", methods=["POST"]
)
def complete_automation_companion_task(companion_id):
    link = get_or_404(AutomationCompanionTask, companion_id)
    return jsonify(complete_companion_task(link.id))


@automation_companion_bp.route(
    "/automation_companion_tasks/by-task/<int:task_id>", methods=["GET"]
)
def get_automation_companion_by_task(task_id):
    link = AutomationCompanionTask.query.filter_by(task_id=task_id).first()
    if link is None:
        return jsonify({"error": "companion task not found"}), 404
    return jsonify(link.to_dict())
