from flask import Blueprint, jsonify, request
from sqlalchemy import or_

from sqlalchemy import case

from models import Block, File, Task, TaskView, Topic, db
from routes.helpers import active_query, apply_updates, get_or_404
from services.automation_dispatcher import dispatch_file_changed
from services.task_view_assign import assign_task_view
from services.automation_topics import AUTOMATIONS_TOPIC_KEY
from services.automation_definitions import (
    eager_companion_trigger_task,
    get_definition,
    uses_companion_trigger_task,
)
from services.automation_params import normalize_params, trigger_config
from services.automation_trigger import handle_task_status_change
from services.automation_trigger_lookup import (
    rule_keys_for_trigger_task,
    trigger_task_ids,
)
from services.task_list_order import (
    move_task_to_list_block,
    next_list_order_index,
    reorder_tasks_in_list_block,
)

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
    block = get_or_404(Block, block_id)
    referenced_ids = _referenced_task_ids_for_list_block(block)
    tasks = (
        active_query(Task)
        .filter(or_(Task.block_id == block_id, Task.id.in_(referenced_ids)))
        .order_by(
            case((Task.status == "done", 1), else_=0),
            Task.list_order_index,
            Task.id,
        )
        .all()
    )
    return jsonify([t.to_dict() for t in tasks])


def _referenced_task_ids_for_list_block(list_block):
    if list_block.type != "task_list" or list_block.file_id is None:
        return []
    content = list_block.content or {}
    if content.get("generated_by") != "project_summary_update":
        return []

    ids = []
    blocks = (
        active_query(Block)
        .filter_by(file_id=list_block.file_id)
        .order_by(Block.order_index, Block.id)
        .all()
    )
    for block in blocks:
        if block.type != "task":
            continue
        content = block.content or {}
        if content.get("generated_by") != "project_summary_update":
            continue
        if content.get("generated_task_list_block_id") != list_block.id:
            continue
        task_id = content.get("task_id")
        if task_id is not None:
            ids.append(int(task_id))
    return ids


def _is_idle_event_companion_trigger(task, companions):
    if companions:
        return False
    if task.status != "done":
        return False
    from models import AutomationRule

    for rule in AutomationRule.query.all():
        definition = get_definition(rule.key, rule.action_type)
        if not uses_companion_trigger_task(definition):
            continue
        if eager_companion_trigger_task(definition):
            continue
        params = normalize_params(rule.params, rule.key, rule.action_type)
        trigger = trigger_config(params) or {}
        if int(trigger.get("task_id") or 0) == int(task.id):
            return True
    return False


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
    rows = rows.order_by(
        TaskView.section_name.nulls_last(),
        TaskView.order_index,
        Task.id,
    ).all()
    from services.automation_companion import pending_companions_by_task_ids

    task_ids = [task.id for task, _, _ in rows]
    companions_by_task = pending_companions_by_task_ids(task_ids)
    trigger_ids = trigger_task_ids()
    visible_rows = []
    for task, task_view, topic in rows:
        companions = companions_by_task.get(task.id, [])
        if _is_idle_event_companion_trigger(task, companions):
            from services.automation_trigger import hide_idle_companion_trigger_from_view

            hide_idle_companion_trigger_from_view(task.id)
            continue
        visible_rows.append((task, task_view, topic, companions))
    return jsonify(
        [
            _enrich_task_row(
                task,
                task_view,
                topic,
                companions,
                trigger_ids,
            )
            for task, task_view, topic, companions in visible_rows
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
    block_id = data.get("block_id")
    if block_id is not None:
        task.list_order_index = next_list_order_index(int(block_id))

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
        {"block_id", "list_order_index", "title", "status", "due_date", "archived_at"},
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


@tasks_bp.route("/blocks/<int:block_id>/tasks/reorder", methods=["POST"])
def reorder_tasks_for_list_block(block_id):
    block = get_or_404(Block, block_id)
    if block.type != "task_list":
        return jsonify({"error": "block must be a task_list"}), 400

    data = request.get_json(silent=True) or {}
    task_ids = data.get("task_ids")
    if not isinstance(task_ids, list) or not task_ids:
        return jsonify({"error": "task_ids must be a non-empty list"}), 400
    if not all(isinstance(task_id, int) for task_id in task_ids):
        return jsonify({"error": "task_ids must be integers"}), 400

    try:
        tasks = reorder_tasks_in_list_block(block_id, task_ids)
    except ValueError as exc:
        return jsonify({"error": str(exc)}), 400

    db.session.commit()
    dispatch_file_changed(block.file_id, "tasks_reordered", {"block_id": block_id})
    return jsonify([task.to_dict() for task in tasks])


@tasks_bp.route("/blocks/<int:block_id>/tasks/move", methods=["POST"])
def move_task_for_list_block(block_id):
    block = get_or_404(Block, block_id)
    if block.type != "task_list":
        return jsonify({"error": "block must be a task_list"}), 400

    data = request.get_json(silent=True) or {}
    task_id = data.get("task_id")
    if task_id is None:
        return jsonify({"error": "task_id is required"}), 400

    insert_index = data.get("insert_index", 0)
    if not isinstance(insert_index, int):
        return jsonify({"error": "insert_index must be an integer"}), 400

    target_done = bool(data.get("target_done", False))

    try:
        result = move_task_to_list_block(
            int(task_id),
            block_id,
            insert_index_in_zone=insert_index,
            target_done=target_done,
        )
    except ValueError as exc:
        return jsonify({"error": str(exc)}), 400

    db.session.commit()
    dispatch_file_changed(block.file_id, "task_moved", {"task_id": int(task_id)})
    return jsonify(
        {
            "task": result["task"].to_dict(),
            "target_tasks": [task.to_dict() for task in result["target_tasks"]],
            "source_tasks": [task.to_dict() for task in result["source_tasks"]],
            "source_block_id": result["source_block_id"],
        }
    )


@tasks_bp.route("/tasks/<int:task_id>/view", methods=["PUT"])
def assign_task_view_route(task_id):
    task = get_or_404(Task, task_id)
    data = request.get_json(silent=True) or {}
    view_type = data.get("view_type")
    if view_type is not None and not isinstance(view_type, str):
        return jsonify({"error": "view_type must be a string or null"}), 400

    clear_section = bool(data.get("clear_section"))
    section_name = data.get("section_name")
    if clear_section:
        section_name = None
    elif "section_name" not in data and view_type is not None:
        existing = (
            TaskView.query.filter_by(task_id=task.id)
            .order_by(TaskView.id)
            .first()
        )
        if existing is not None and existing.view_type == view_type:
            section_name = existing.section_name

    membership = assign_task_view(
        task.id,
        view_type,
        section_name=section_name,
        topic_key=data.get("topic_key"),
        order_index=data.get("order_index"),
        clear_section=clear_section,
    )
    db.session.commit()
    dispatch_file_changed(
        _file_id_for_task(task),
        "task_view_assigned",
        {"task_id": task.id, "view_type": view_type},
    )
    if membership is None:
        return jsonify({"task_id": task.id, "view_type": None}), 200
    return jsonify(membership.to_dict())


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
