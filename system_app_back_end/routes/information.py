from flask import Blueprint, jsonify, request

from models import InformationPiece, db
from routes.helpers import apply_updates, get_or_404

information_bp = Blueprint("information", __name__)


@information_bp.route("/information/<int:info_id>", methods=["GET"])
def get_information(info_id):
    return jsonify(get_or_404(InformationPiece, info_id).to_dict())


@information_bp.route("/information/<int:info_id>", methods=["PATCH"])
def update_information(info_id):
    info = get_or_404(InformationPiece, info_id)
    data = request.get_json(silent=True) or {}
    if "metadata" in data:
        info.metadata_ = data["metadata"]
    apply_updates(
        info,
        data,
        {"title", "body", "archived_at"},
        datetime_fields={"archived_at"},
    )
    db.session.commit()
    return jsonify(info.to_dict())
