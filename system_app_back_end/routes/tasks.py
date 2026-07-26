from flask import Blueprint, jsonify, request

from models import Task, db
from routes.helpers import active_query, apply_updates, get_or_404

tasks_bp = Blueprint("tasks", __name__)


@tasks_bp.route("/tasks/<int:task_id>", methods=["GET"])
def get_task(task_id):
    return jsonify(get_or_404(Task, task_id).to_dict())


@tasks_bp.route("/tasks", methods=["GET"])
def list_tasks():
    tasks = active_query(Task).order_by(Task.list_order_index, Task.id).all()
    return jsonify([t.to_dict() for t in tasks])


@tasks_bp.route("/tasks/<int:task_id>", methods=["PATCH"])
def update_task(task_id):
    task = get_or_404(Task, task_id)
    data = request.get_json(silent=True) or {}
    apply_updates(
        task,
        data,
        {"title", "status", "due_date", "list_order_index", "archived_at"},
        datetime_fields={"due_date", "archived_at"},
    )
    db.session.commit()
    return jsonify(task.to_dict())


@tasks_bp.route("/tasks/<int:task_id>/toggle", methods=["POST"])
def toggle_task(task_id):
    task = get_or_404(Task, task_id)
    task.status = "done" if task.status != "done" else "active"
    db.session.commit()
    return jsonify(task.to_dict())
