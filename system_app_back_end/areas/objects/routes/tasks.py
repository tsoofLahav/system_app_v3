from flask import Blueprint, jsonify, request

from models import Link, ObjectEmbed, Task, ViewTaskMembership, db
from shared.bootstrap import default_workspace_id
from shared.helpers import active_query, apply_updates, get_or_404
from areas.objects.services import task_ops
from areas.objects.services.delete_cascade import delete_task_cascade
from areas.objects.services.object_graph import (
    TASK_LINK_TYPE,
    file_id_for_task,
    info_peer_dict,
    normalize_description_anchor,
    patch_description_anchor,
    workspace_id_for_task,
)

tasks_bp = Blueprint("tasks", __name__)


def _topic_order_index(item, fallback):
    raw = item.get("topic_order_index")
    if raw is None:
        raw = item.get("order_index", fallback)
    try:
        return int(raw)
    except (TypeError, ValueError):
        return fallback


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
    if data.get("status") == task_ops.PENDING and not task_ops.task_has_view(task):
        raise ValueError("pending tasks need a view")
    if "status" in data:
        task_ops.sync_status_with_memberships(task)
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
    task = get_or_404(Task, task_id)
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
            topic_order_index=_topic_order_index(item, index),
            section_flag=item.get("section_flag"),
            topic_key=item.get("topic_key"),
        )
        db.session.add(row)
    db.session.flush()
    task_ops.sync_status_with_memberships(task)
    db.session.commit()
    return list_task_memberships(task_id)


@tasks_bp.route("/tasks/<int:task_id>/links", methods=["POST"])
def create_task_description_link(task_id):
    task = get_or_404(Task, task_id)
    data = request.get_json(silent=True) or {}
    kind = data.get("kind") or "description"
    if kind != "description":
        return jsonify({"error": "task links must be kind=description"}), 400

    target_object_id = data.get("target_object_id") or data.get("target_id")
    if target_object_id is None:
        return jsonify({"error": "target_object_id required"}), 400
    target = get_or_404(ObjectEmbed, int(target_object_id))
    if target.type != "info":
        return jsonify({"error": "description links require an info target"}), 400

    workspace_id = workspace_id_for_task(task) or default_workspace_id()
    if not workspace_id:
        return jsonify({"error": "workspace_id required"}), 400

    raw_anchor = data.get("anchor")
    if not isinstance(raw_anchor, dict):
        raw_anchor = {}
    if not str(raw_anchor.get("segment_id") or "").strip():
        raw_anchor = {**raw_anchor, "segment_id": f"task:{task.id}"}
    try:
        anchor = normalize_description_anchor(raw_anchor)
    except ValueError as err:
        return jsonify({"error": str(err)}), 400
    if "file_id" not in anchor:
        host_file_id = file_id_for_task(task)
        if host_file_id is not None:
            anchor["file_id"] = host_file_id

    link = Link(
        workspace_id=workspace_id,
        source_type=TASK_LINK_TYPE,
        source_id=task.id,
        target_type="info",
        target_id=target.id,
        kind="description",
        anchor=anchor,
        label=data.get("label"),
    )
    db.session.add(link)
    db.session.commit()
    data_out = link.to_dict()
    data_out["peer"] = info_peer_dict(target, target.id)
    return jsonify(data_out), 201


@tasks_bp.route("/tasks/<int:task_id>/links/<int:link_id>", methods=["PATCH"])
def patch_task_description_link(task_id, link_id):
    get_or_404(Task, task_id)
    link = Link.query.filter_by(id=link_id).first()
    if link is None:
        return jsonify({"error": "not found"}), 404
    if link.source_type != TASK_LINK_TYPE or link.source_id != task_id:
        return jsonify({"error": "not found"}), 404
    data = request.get_json(silent=True) or {}
    try:
        patch_description_anchor(link, data.get("anchor"))
    except ValueError as err:
        return jsonify({"error": str(err)}), 400
    db.session.commit()
    data_out = link.to_dict()
    target = db.session.get(ObjectEmbed, link.target_id)
    data_out["peer"] = info_peer_dict(target, link.target_id)
    return jsonify(data_out)


@tasks_bp.route("/tasks/<int:task_id>/links/<int:link_id>", methods=["DELETE"])
def delete_task_description_link(task_id, link_id):
    get_or_404(Task, task_id)
    link = Link.query.filter_by(id=link_id).first()
    if link is None:
        return jsonify({"error": "not found"}), 404
    if link.source_type != TASK_LINK_TYPE or link.source_id != task_id:
        return jsonify({"error": "not found"}), 404
    db.session.delete(link)
    db.session.commit()
    return "", 204
