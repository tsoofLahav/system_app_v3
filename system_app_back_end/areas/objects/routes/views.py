from flask import Blueprint, jsonify, request

from models import File, ObjectEmbed, Task, Topic, View, ViewTaskMembership, db
from shared.helpers import active_query, apply_updates, get_or_404
from shared.bootstrap import default_workspace_id
from areas.objects.services.delete_cascade import delete_view_cascade

views_bp = Blueprint("views", __name__)


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
    db.session.commit()
    return jsonify(view.to_dict())


@views_bp.route("/views/<int:view_id>", methods=["DELETE"])
def delete_view(view_id):
    get_or_404(View, view_id)
    delete_view_cascade(view_id)
    db.session.commit()
    return "", 204


def _task_dict_with_topic(task: Task) -> dict:
    """Include home-topic fields so the view pane can colour topic frames."""
    data = task.to_dict()
    if not task.task_list_id:
        return data
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
            section_flag=item.get("section_flag"),
            topic_key=item.get("topic_key"),
        )
        db.session.add(row)
    db.session.commit()
    return list_memberships(view_id)
