from flask import Blueprint, jsonify, request

from models import db
from services.process_documentation_input import submit_process_documentation_input

process_documentation_inputs_bp = Blueprint(
    "process_documentation_inputs",
    __name__,
)


@process_documentation_inputs_bp.route(
    "/process_documentation_inputs",
    methods=["POST"],
)
def create_process_documentation_input():
    data = request.get_json(silent=True) or {}
    topic_id = data.get("topic_id")
    if topic_id is None:
        return jsonify({"error": "topic_id is required"}), 400

    try:
        result = submit_process_documentation_input(
            topic_id=int(topic_id),
            text=str(data.get("text") or ""),
            grade=int(data.get("grade")),
            date=data.get("date"),
            timezone=data.get("timezone"),
        )
        db.session.commit()
        return jsonify(result), 201
    except ValueError as error:
        db.session.rollback()
        return jsonify({"error": str(error)}), 400
    except Exception:
        db.session.rollback()
        raise
