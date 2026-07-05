from flask import Blueprint, jsonify, request

from models import Block, File, Task, TaskView, Topic, db
from routes.helpers import active_query, apply_updates, get_or_404
from services.automation_dispatcher import dispatch_file_changed
from services.automation_topics import AUTOMATIONS_TOPIC_KEY
from services.automation_trigger import handle_task_status_change
from services.automation_trigger_lookup import (
    rule_keys_for_trigger_task,
    trigger_task_ids,
)
from services.delete_cascade import delete_task_cascade

tasks_bp = Blueprint("tasks", __name__)


def _file_id_for_task(task):
    if task.block_id is None:
        return None
    block = db.session.get(Block, task.block_id)
    return block.file_id if block is not None else None


def _topic_name_for_row(task_view, topic, companion):
    if task_view.topic_key == AUTOMATIONS_TOPIC_KEY:
        return AUTOMATIONS_TOPIC_KEY
    if topic is not None:
        return topic.name
    return None


def _enrich_task_row(task, task_view, topic, companions=None, trigger_ids=None):
    companions = companions or []
    item = task.to_dict()
    item["task_view_id"] = task_view.id
    item["view_type"] = task_view.view_type
    item["section_name"] = task_view.section_name
    item["section_flag"] = task_view.section_flag
    item["topic_key"] = task_view.topic_key
    item["topic_name"] = _topic_name_for_row(task_view, topic, companions[0] if companions else None)
    if companions:
        companion = companions[0]
        payload = companion.payload if companion.payload is not None else {}
        if payload.get("topic_name"):
            item["subject_topic_name"] = payload["topic_name"]
        if companion.topic_id is not None:
            item["subject_topic_id"] = companion.topic_id
        item["companion_task_id"] = companion.id
        item["flow_key"] = companion.flow_key
        item["companion_payload"] = payload
        item["automation_rule_key"] = companion.rule_key
        item["pending_companion_count"] = len(companions)
        item["has_pending_companion_flow"] = True
    else:
        item["pending_companion_count"] = 0
        item["has_pending_companion_flow"] = False
        if topic is not None:
            item["topic_id"] = topic.id
    trigger_ids = trigger_ids if trigger_ids is not None else trigger_task_ids()
    if task.id in trigger_ids:
        item["is_automation_trigger"] = True
        keys = rule_keys_for_trigger_task(task.id, enabled_only=False)
        if keys:
            item["automation_rule_key"] = keys[0]
    return item


@tasks_bp.route("/tasks", methods=["GET"])
def list_tasks():
    tasks = active_query(Task).order_by(Task.id).all()
    return jsonify([t.to_dict() for t in tasks])


@tasks_bp.route("/tasks/<int:task_id>", methods=["GET"])
def get_task(task_id):
    return jsonify(get_or_404(Task, task_id).to_dict())


@tasks_bp.route("/blocks/<int:block_id>/tasks", methods=["GET"])
def list_tasks_by_block(block_id):
    tasks = active_query(Task).filter_by(block_id=block_id).order_by(Task.id).all()
    return jsonify([t.to_dict() for t in tasks])


@tasks_bp.route("/tasks/view/<view_type>", methods=["GET"])
def list_tasks_by_view(view_type):
    from services.task_view_flags import IMPORTANT_SECTION_FLAG

    important_only = request.args.get("important", "").lower() in {
        "1",
        "true",
        "yes",
    }
    rows = (
        db.session.query(Task, TaskView, Topic)
        .join(TaskView, TaskView.task_id == Task.id)
        .outerjoin(Block, Task.block_id == Block.id)
        .outerjoin(File, Block.file_id == File.id)
        .outerjoin(Topic, File.topic_id == Topic.id)
        .filter(TaskView.view_type == view_type)
        .filter(TaskView.task_id.isnot(None))
        .filter(Task.archived_at.is_(None))
        .filter(
            (Block.id.is_(None))
            | (
                Block.archived_at.is_(None)
                & File.archived_at.is_(None)
                & Topic.archived_at.is_(None)
            )
        )
    )
    if important_only:
        rows = rows.filter(TaskView.section_flag == IMPORTANT_SECTION_FLAG)
    rows = rows.order_by(TaskView.section_name.nulls_last(), Task.id).all()
    from services.automation_companion import pending_companions_by_task_ids

    task_ids = [task.id for task, _, _ in rows]
    companions_by_task = pending_companions_by_task_ids(task_ids)
    trigger_ids = trigger_task_ids()
    return jsonify(
        [
            _enrich_task_row(
                task,
                task_view,
                topic,
                companions_by_task.get(task.id, []),
                trigger_ids,
            )
            for task, task_view, topic in rows
        ]
    )


@tasks_bp.route("/tasks", methods=["POST"])
def create_task():
    data = request.get_json(silent=True) or {}
    if "title" not in data:
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
    dispatch_file_changed(
        _file_id_for_task(task),
        "task_created",
        {"task_id": task.id},
    )
    return jsonify(task.to_dict()), 201


@tasks_bp.route("/tasks/<int:task_id>", methods=["PATCH"])
def update_task(task_id):
    from flask import current_app

    from services.automation_runner import kick_run_async

    task = get_or_404(Task, task_id)
    data = request.get_json(silent=True) or {}
    previous_status = task.status
    apply_updates(
        task,
        data,
        {"block_id", "title", "status", "due_date", "archived_at"},
        datetime_fields={"due_date", "archived_at"},
    )
    db.session.commit()

    run_ids = []
    if "status" in data and not data.get("_skip_automation_trigger"):
        run_ids = handle_task_status_change(task, previous_status)
        if run_ids:
            app = current_app._get_current_object()
            for run_id in run_ids:
                kick_run_async(app, run_id)

    dispatch_file_changed(
        _file_id_for_task(task),
        "task_updated",
        {"task_id": task.id},
    )

    payload = task.to_dict()
    if run_ids:
        payload["automation_run_ids"] = run_ids
    elif "status" in data and rule_keys_for_trigger_task(
        task.id, enabled_only=False
    ):
        if previous_status != "done" or task.status != "active":
            payload["automation_trigger_skipped"] = "uncheck_to_run"
        elif not rule_keys_for_trigger_task(task.id):
            payload["automation_trigger_skipped"] = "not_trigger_task"
    return jsonify(payload)


@tasks_bp.route("/tasks/<int:task_id>", methods=["DELETE"])
def delete_task(task_id):
    if task_id in trigger_task_ids():
        return jsonify({"error": "cannot delete automation trigger task"}), 403
    task = get_or_404(Task, task_id)
    file_id = _file_id_for_task(task)
    delete_task_cascade(task_id)
    db.session.commit()
    dispatch_file_changed(file_id, "task_deleted", {"task_id": task_id})
    return "", 204
