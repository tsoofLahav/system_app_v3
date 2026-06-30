from flask import Blueprint, jsonify, request

from models import TaskView, db
from routes.helpers import apply_updates, get_or_404
from services.task_view_flags import (
    apply_section_flag_to_membership,
    propagate_section_flag,
)

task_views_bp = Blueprint("task_views", __name__)


@task_views_bp.route("/task_views", methods=["GET"])
def list_task_views():
    views = (
        TaskView.query.filter(TaskView.task_id.isnot(None))
        .order_by(TaskView.order_index, TaskView.id)
        .all()
    )
    return jsonify([v.to_dict() for v in views])


@task_views_bp.route("/task_views/<int:view_id>", methods=["GET"])
def get_task_view(view_id):
    return jsonify(get_or_404(TaskView, view_id).to_dict())


@task_views_bp.route("/task_views/by-view/<view_type>", methods=["GET"])
def list_task_views_by_type(view_type):
    views = (
        TaskView.query.filter_by(view_type=view_type)
        .filter(TaskView.task_id.isnot(None))
        .order_by(TaskView.order_index, TaskView.id)
        .all()
    )
    return jsonify([v.to_dict() for v in views])


@task_views_bp.route("/task_views/sections/<view_type>", methods=["GET"])
def list_sections_for_view(view_type):
    """Section placeholders: rows with task_id NULL and section_name set."""
    rows = (
        TaskView.query.filter_by(view_type=view_type)
        .filter(TaskView.task_id.is_(None))
        .filter(TaskView.section_name.isnot(None))
        .order_by(TaskView.order_index, TaskView.id)
        .all()
    )
    return jsonify([v.to_dict() for v in rows])


@task_views_bp.route("/task_views", methods=["POST"])
def create_task_view():
    data = request.get_json(silent=True) or {}
    view_type = data.get("view_type")
    if not view_type:
        return jsonify({"error": "view_type is required"}), 400

    task_id = data.get("task_id")
    section_name = data.get("section_name")

    if task_id is None:
        if not section_name:
            return jsonify({"error": "section_name is required for section placeholders"}), 400
        max_order = (
            db.session.query(db.func.max(TaskView.order_index))
            .filter_by(view_type=view_type)
            .filter(TaskView.task_id.is_(None))
            .scalar()
        ) or -1
        view = TaskView(
            task_id=None,
            view_type=view_type,
            section_name=section_name,
            order_index=data.get("order_index", max_order + 1),
            section_flag=data.get("section_flag"),
        )
    else:
        view = TaskView(
            task_id=task_id,
            view_type=view_type,
            section_name=section_name,
            topic_key=data.get("topic_key"),
        )
        apply_section_flag_to_membership(view)

    db.session.add(view)
    db.session.commit()
    return jsonify(view.to_dict()), 201


@task_views_bp.route("/task_views/<int:view_id>", methods=["PATCH"])
def update_task_view(view_id):
    view = get_or_404(TaskView, view_id)
    data = request.get_json(silent=True) or {}
    apply_updates(
        view,
        data,
        {"task_id", "view_type", "section_name", "order_index", "section_flag", "topic_key"},
    )

    if view.task_id is None and "section_flag" in data:
        propagate_section_flag(view.view_type, view.section_name, view.section_flag)
    elif view.task_id is not None and "section_name" in data:
        apply_section_flag_to_membership(view)

    db.session.commit()
    return jsonify(view.to_dict())


@task_views_bp.route("/task_views/<int:view_id>", methods=["DELETE"])
def delete_task_view(view_id):
    view = get_or_404(TaskView, view_id)
    db.session.delete(view)
    db.session.commit()
    return "", 204
