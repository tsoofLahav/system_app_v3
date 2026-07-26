from flask import Blueprint, jsonify, request

from models import Task, TaskList, db
from routes.helpers import get_or_404
from services.task_list_order import (
    move_task_to_list,
    next_list_order_index,
    reorder_tasks_in_list,
    tasks_for_list,
)

task_lists_bp = Blueprint("task_lists", __name__)


@task_lists_bp.route("/task-lists/<int:task_list_id>", methods=["GET"])
def get_task_list(task_list_id):
    task_list = get_or_404(TaskList, task_list_id)
    tasks = tasks_for_list(task_list_id)
    data = task_list.to_dict()
    data["tasks"] = [t.to_dict() for t in tasks]
    return jsonify(data)


@task_lists_bp.route("/task-lists/<int:task_list_id>/tasks", methods=["GET"])
def list_tasks(task_list_id):
    get_or_404(TaskList, task_list_id)
    return jsonify([t.to_dict() for t in tasks_for_list(task_list_id)])


@task_lists_bp.route("/task-lists/<int:task_list_id>/tasks", methods=["POST"])
def create_task(task_list_id):
    get_or_404(TaskList, task_list_id)
    data = request.get_json(silent=True) or {}
    title = data.get("title") or "New task"
    status = data.get("status") or "active"
    order_index = data.get("list_order_index")
    if order_index is None:
        order_index = next_list_order_index(task_list_id)

    task = Task(
        task_list_id=task_list_id,
        title=title,
        status=status,
        list_order_index=order_index,
    )
    db.session.add(task)
    db.session.commit()
    return jsonify(task.to_dict()), 201


@task_lists_bp.route("/task-lists/<int:task_list_id>/tasks/order", methods=["PUT"])
def reorder_tasks(task_list_id):
    get_or_404(TaskList, task_list_id)
    data = request.get_json(silent=True) or {}
    ordered_ids = data.get("ordered_task_ids") or []
    try:
        tasks = reorder_tasks_in_list(task_list_id, ordered_ids)
    except ValueError as error:
        return jsonify({"error": str(error)}), 400
    db.session.commit()
    return jsonify([t.to_dict() for t in tasks])


@task_lists_bp.route("/tasks/<int:task_id>/move", methods=["POST"])
def move_task(task_id):
    data = request.get_json(silent=True) or {}
    target_task_list_id = data.get("target_task_list_id")
    if target_task_list_id is None:
        return jsonify({"error": "target_task_list_id required"}), 400
    try:
        result = move_task_to_list(
            task_id,
            int(target_task_list_id),
            insert_index_in_zone=int(data.get("insert_index_in_zone", 0)),
            target_done=bool(data.get("target_done", False)),
        )
    except ValueError as error:
        return jsonify({"error": str(error)}), 400
    db.session.commit()
    return jsonify(
        {
            "task": result["task"].to_dict(),
            "target_tasks": [t.to_dict() for t in result["target_tasks"]],
            "source_tasks": [t.to_dict() for t in result["source_tasks"]],
            "source_task_list_id": result["source_task_list_id"],
        }
    )
