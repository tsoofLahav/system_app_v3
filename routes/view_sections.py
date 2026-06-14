from flask import Blueprint, jsonify, request

from models import ViewSection, db
from routes.helpers import apply_updates, get_or_404

view_sections_bp = Blueprint("view_sections", __name__)


@view_sections_bp.route("/view_sections", methods=["GET"])
def list_view_sections():
    view_type = request.args.get("view_type")
    query = ViewSection.query
    if view_type:
        query = query.filter_by(view_type=view_type)
    sections = query.order_by(ViewSection.order_index, ViewSection.id).all()
    return jsonify([s.to_dict() for s in sections])


@view_sections_bp.route("/view_sections/by-view/<view_type>", methods=["GET"])
def list_view_sections_by_type(view_type):
    sections = (
        ViewSection.query.filter_by(view_type=view_type)
        .order_by(ViewSection.order_index, ViewSection.id)
        .all()
    )
    return jsonify([s.to_dict() for s in sections])


@view_sections_bp.route("/view_sections/<int:section_id>", methods=["GET"])
def get_view_section(section_id):
    return jsonify(get_or_404(ViewSection, section_id).to_dict())


@view_sections_bp.route("/view_sections", methods=["POST"])
def create_view_section():
    data = request.get_json(silent=True) or {}
    if not data.get("view_type") or not data.get("name"):
        return jsonify({"error": "view_type and name are required"}), 400

    section = ViewSection(
        view_type=data["view_type"],
        name=data["name"],
        order_index=data.get("order_index", 0),
    )
    db.session.add(section)
    db.session.commit()
    return jsonify(section.to_dict()), 201


@view_sections_bp.route("/view_sections/<int:section_id>", methods=["PATCH"])
def update_view_section(section_id):
    section = get_or_404(ViewSection, section_id)
    data = request.get_json(silent=True) or {}
    apply_updates(section, data, {"view_type", "name", "order_index"})
    db.session.commit()
    return jsonify(section.to_dict())


@view_sections_bp.route("/view_sections/<int:section_id>", methods=["DELETE"])
def delete_view_section(section_id):
    section = get_or_404(ViewSection, section_id)
    db.session.delete(section)
    db.session.commit()
    return "", 204
