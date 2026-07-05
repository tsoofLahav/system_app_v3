from datetime import datetime

from flask import Blueprint, jsonify, request

from models import TaskResetAcknowledgement, db
from routes.helpers import get_or_404

task_reset_acknowledgements_bp = Blueprint(
    "task_reset_acknowledgements",
    __name__,
)


@task_reset_acknowledgements_bp.route(
    "/task_reset_acknowledgements",
    methods=["GET"],
)
def list_task_reset_acknowledgements():
    query = TaskResetAcknowledgement.query.order_by(
        TaskResetAcknowledgement.created_at.desc(),
        TaskResetAcknowledgement.id.desc(),
    )
    view_type = request.args.get("view_type")
    status = request.args.get("status", "pending")
    if view_type:
        query = query.filter_by(view_type=view_type)
    if status:
        statuses = [value.strip() for value in status.split(",") if value.strip()]
        if statuses:
            query = query.filter(TaskResetAcknowledgement.status.in_(statuses))
    limit = request.args.get("limit", default=20, type=int)
    rows = query.limit(limit).all()
    return jsonify([row.to_dict() for row in rows])


@task_reset_acknowledgements_bp.route(
    "/task_reset_acknowledgements/<int:ack_id>/approve",
    methods=["POST"],
)
def approve_task_reset_acknowledgement(ack_id):
    acknowledgement = get_or_404(TaskResetAcknowledgement, ack_id)
    acknowledgement.status = "approved"
    acknowledgement.approved_at = datetime.utcnow()
    db.session.commit()
    return jsonify(acknowledgement.to_dict())
