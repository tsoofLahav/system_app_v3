from flask import Blueprint, jsonify, request

from models import Task, ViewTaskMembership, db
from shared.helpers import active_query, apply_updates, get_or_404
from areas.objects.services import task_ops
from areas.objects.services.delete_cascade import delete_task_cascade

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
        {"title", "status", "due_date", "list_order_index", "archived_at", "task_list_id"},
        datetime_fields={"due_date", "archived_at"},
    )
    db.session.commit()
    return jsonify(task.to_dict())


@tasks_bp.route("/tasks/<int:task_id>/toggle", methods=["POST"])
def toggle_task(task_id):
    task = task_ops.toggle_task(get_or_404(Task, task_id))
    db.session.commit()
    return jsonify(task.to_dict())


@tasks_bp.route("/tasks/<int:task_id>", methods=["DELETE"])
def delete_task(task_id):
    get_or_404(Task, task_id)
    delete_task_cascade(task_id)
    db.session.commit()
    return "", 204


@tasks_bp.route("/tasks/<int:task_id>/memberships", methods=["GET"])
def list_task_memberships(task_id):
    get_or_404(Task, task_id)
    rows = (
        ViewTaskMembership.query.filter_by(task_id=task_id)
        .order_by(ViewTaskMembership.order_index, ViewTaskMembership.id)
        .all()
    )
    return jsonify([r.to_dict() for r in rows])


@tasks_bp.route("/tasks/<int:task_id>/memberships", methods=["PUT"])
def replace_task_memberships(task_id):
    get_or_404(Task, task_id)
    data = request.get_json(silent=True) or {}
    memberships = data.get("memberships") or []

    ViewTaskMembership.query.filter_by(task_id=task_id).delete(
        synchronize_session=False
    )
    for index, item in enumerate(memberships):
        row = ViewTaskMembership(
            view_id=item["view_id"],
            task_id=task_id,
            section_name=item.get("section_name"),
            order_index=item.get("order_index", index),
            section_flag=item.get("section_flag"),
            topic_key=item.get("topic_key"),
        )
        db.session.add(row)
    db.session.commit()
    return list_task_memberships(task_id)
