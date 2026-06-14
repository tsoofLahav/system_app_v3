from flask import Blueprint, jsonify, request

from models import Block, File, Task, TaskView, Topic, db
from routes.helpers import apply_updates, get_or_404

tasks_bp = Blueprint("tasks", __name__)


@tasks_bp.route("/tasks", methods=["GET"])
def list_tasks():
    tasks = Task.query.order_by(Task.id).all()
    return jsonify([t.to_dict() for t in tasks])


@tasks_bp.route("/tasks/<int:task_id>", methods=["GET"])
def get_task(task_id):
    return jsonify(get_or_404(Task, task_id).to_dict())


@tasks_bp.route("/blocks/<int:block_id>/tasks", methods=["GET"])
def list_tasks_by_block(block_id):
    tasks = Task.query.filter_by(block_id=block_id).order_by(Task.id).all()
    return jsonify([t.to_dict() for t in tasks])


@tasks_bp.route("/tasks/view/<view_type>", methods=["GET"])
def list_tasks_by_view(view_type):
    rows = (
        db.session.query(Task, TaskView, Topic)
        .join(TaskView, TaskView.task_id == Task.id)
        .outerjoin(Block, Task.block_id == Block.id)
        .outerjoin(File, Block.file_id == File.id)
        .outerjoin(Topic, File.topic_id == Topic.id)
        .filter(TaskView.view_type == view_type)
        .filter(TaskView.task_id.isnot(None))
        .order_by(TaskView.section_name.nulls_last(), Task.id)
        .all()
    )
    result = []
    for task, task_view, topic in rows:
        item = task.to_dict()
        item["task_view_id"] = task_view.id
        item["view_type"] = task_view.view_type
        item["section_name"] = task_view.section_name
        item["topic_id"] = topic.id if topic else None
        item["topic_name"] = topic.name if topic else None
        result.append(item)
    return jsonify(result)


@tasks_bp.route("/tasks", methods=["POST"])
def create_task():
    data = request.get_json(silent=True) or {}
    if not data.get("title"):
        return jsonify({"error": "title is required"}), 400

    due_date = data.get("due_date")
    if due_date is not None and isinstance(due_date, str):
        from routes.helpers import parse_datetime

        due_date = parse_datetime(due_date)

    task = Task(
        block_id=data.get("block_id"),
        title=data["title"],
        status=data.get("status", "active"),
        due_date=due_date,
    )

    db.session.add(task)
    db.session.commit()
    return jsonify(task.to_dict()), 201


@tasks_bp.route("/tasks/<int:task_id>", methods=["PATCH"])
def update_task(task_id):
    task = get_or_404(Task, task_id)
    data = request.get_json(silent=True) or {}
    apply_updates(
        task,
        data,
        {"block_id", "title", "status", "due_date"},
        datetime_fields={"due_date"},
    )
    db.session.commit()
    return jsonify(task.to_dict())


@tasks_bp.route("/tasks/<int:task_id>", methods=["DELETE"])
def delete_task(task_id):
    task = get_or_404(Task, task_id)
    db.session.delete(task)
    db.session.commit()
    return "", 204
