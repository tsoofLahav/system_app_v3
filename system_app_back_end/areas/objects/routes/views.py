from flask import Blueprint, jsonify, request

from models import File, ObjectEmbed, Task, TaskList, Topic, View, ViewTaskMembership, db
from shared.helpers import active_query, apply_updates, get_or_404
from shared.bootstrap import default_workspace_id
from areas.objects.services.delete_cascade import delete_view_cascade
from areas.objects.services.task_list_order import next_list_order_index

views_bp = Blueprint("views", __name__)


def _topic_order_index(item, fallback):
    raw = item.get("topic_order_index")
    if raw is None:
        raw = item.get("order_index", fallback)
    try:
        return int(raw)
    except (TypeError, ValueError):
        return fallback


@views_bp.route("/views", methods=["GET"])
def list_views():
    workspace_id = request.args.get("workspace_id", type=int) or default_workspace_id()
    query = active_query(View)
    if workspace_id:
        query = query.filter_by(workspace_id=workspace_id)
    views = query.order_by(View.order_index, View.id).all()
    return jsonify([v.to_dict() for v in views])


@views_bp.route("/views/<int:view_id>", methods=["GET"])
def get_view(view_id):
    return jsonify(get_or_404(View, view_id).to_dict())


@views_bp.route("/views", methods=["POST"])
def create_view():
    data = request.get_json(silent=True) or {}
    if not data.get("name"):
        return jsonify({"error": "name is required"}), 400
    workspace_id = data.get("workspace_id") or default_workspace_id()
    if not workspace_id:
        return jsonify({"error": "workspace_id is required"}), 400
    view = View(
        workspace_id=workspace_id,
        name=data["name"],
        layout_config=data.get("layout_config") or {},
        order_index=data.get("order_index", 0),
    )
    db.session.add(view)
    db.session.commit()
    return jsonify(view.to_dict()), 201


@views_bp.route("/views/<int:view_id>", methods=["PATCH"])
def update_view(view_id):
    view = get_or_404(View, view_id)
    data = request.get_json(silent=True) or {}
    apply_updates(
        view,
        data,
        {"name", "layout_config", "order_index", "archived_at"},
        datetime_fields={"archived_at"},
    )
    if "layout_config" in data or "name" in data:
        from areas.automations.services.section_windows import ensure_section_windows

        ensure_section_windows(view.workspace_id)
    db.session.commit()
    return jsonify(view.to_dict())


@views_bp.route("/views/<int:view_id>", methods=["DELETE"])
def delete_view(view_id):
    get_or_404(View, view_id)
    delete_view_cascade(view_id)
    db.session.commit()
    return "", 204


def _task_dict_with_topic(task: Task) -> dict:
    """Include home-list title and topic fields for view frames."""
    data = task.to_dict()
    if not task.task_list_id:
        return data
    task_list = db.session.get(TaskList, task.task_list_id)
    if task_list is not None:
        data["task_list_title"] = task_list.title or ""
    obj = ObjectEmbed.query.filter_by(task_list_id=task.task_list_id).first()
    if obj is None:
        return data
    file_row = db.session.get(File, obj.file_id)
    if file_row is None:
        return data
    topic = db.session.get(Topic, file_row.topic_id)
    if topic is None:
        return data
    data["topic_id"] = topic.id
    data["topic_name"] = topic.name
    data["topic_key"] = f"topic_{topic.id}"
    data["topic_color"] = topic.color
    return data


def _blank_text(value):
    if value is None:
        return None
    text = str(value).strip()
    return text or None


@views_bp.route("/views/<int:view_id>/tasks", methods=["POST"])
def create_view_task(view_id):
    """Create a task membership in this view.

    View-created tasks are orphans by default (``task_list_id`` null). Pass
    ``task_list_id`` only when placing into an existing home list.

    Placement is only what this request sends: empty/null ``section_name`` is
    Uncategorized, empty/null ``topic_key`` is No topic. ``after_task_id``
    is insert order — never copy the sibling's section, topic, or list.
    """
    get_or_404(View, view_id)
    data = request.get_json(silent=True) or {}
    title = (
        ""
        if "title" not in data or data.get("title") is None
        else str(data.get("title"))
    )
    status = data.get("status") or "active"
    section_name = _blank_text(data.get("section_name"))
    section_flag = _blank_text(data.get("section_flag"))
    topic_key = _blank_text(data.get("topic_key"))
    after_task_id = data.get("after_task_id")
    task_list_id = data.get("task_list_id")
    if task_list_id is not None:
        task_list_id = int(task_list_id)
        get_or_404(TaskList, task_list_id)

    order_index = (
        next_list_order_index(task_list_id) if task_list_id is not None else 0
    )
    task = Task(
        task_list_id=task_list_id,
        title=title,
        status=status,
        list_order_index=order_index,
        source_automation_id=data.get("source_automation_id"),
        complimentary_role=_blank_text(data.get("complimentary_role")),
    )
    db.session.add(task)
    db.session.flush()

    insert_at = None
    topic_insert_at = None
    if after_task_id is not None:
        for row in ViewTaskMembership.query.filter_by(view_id=view_id).all():
            if row.task_id == int(after_task_id):
                insert_at = (row.order_index or 0) + 1
                topic_insert_at = (row.topic_order_index or 0) + 1
                break

    rows = (
        ViewTaskMembership.query.filter_by(view_id=view_id)
        .order_by(ViewTaskMembership.order_index, ViewTaskMembership.id)
        .all()
    )
    if insert_at is None:
        insert_at = len(rows)
    if topic_insert_at is None:
        topic_insert_at = len(rows)

    for row in rows:
        if (row.order_index or 0) >= insert_at:
            row.order_index = (row.order_index or 0) + 1
        if (row.topic_order_index or 0) >= topic_insert_at:
            row.topic_order_index = (row.topic_order_index or 0) + 1

    db.session.add(
        ViewTaskMembership(
            view_id=view_id,
            task_id=task.id,
            section_name=section_name,
            order_index=insert_at,
            topic_order_index=topic_insert_at,
            section_flag=section_flag,
            topic_key=topic_key,
        )
    )
    db.session.commit()
    return jsonify(_task_dict_with_topic(task)), 201


@views_bp.route("/views/<int:view_id>/memberships", methods=["GET"])
def list_memberships(view_id):
    get_or_404(View, view_id)
    rows = (
        ViewTaskMembership.query.filter_by(view_id=view_id)
        .order_by(ViewTaskMembership.order_index, ViewTaskMembership.id)
        .all()
    )
    result = []
    for row in rows:
        data = row.to_dict()
        if row.task_id:
            task = db.session.get(Task, row.task_id)
            if task:
                data["task"] = _task_dict_with_topic(task)
        result.append(data)
    return jsonify(result)


@views_bp.route("/views/<int:view_id>/memberships", methods=["PUT"])
def replace_memberships(view_id):
    get_or_404(View, view_id)
    data = request.get_json(silent=True) or {}
    memberships = data.get("memberships") or []

    ViewTaskMembership.query.filter_by(view_id=view_id).delete(
        synchronize_session=False
    )
    for index, item in enumerate(memberships):
        row = ViewTaskMembership(
            view_id=view_id,
            task_id=item.get("task_id"),
            section_name=item.get("section_name"),
            order_index=item.get("order_index", index),
            topic_order_index=_topic_order_index(item, index),
            section_flag=item.get("section_flag"),
            topic_key=item.get("topic_key"),
        )
        db.session.add(row)
    db.session.commit()
    return list_memberships(view_id)
