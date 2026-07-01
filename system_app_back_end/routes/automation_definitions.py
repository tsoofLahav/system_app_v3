from flask import Blueprint, jsonify

from services.automation_definitions import AUTOMATION_DEFINITIONS, get_definition

automation_definitions_bp = Blueprint("automation_definitions", __name__)


@automation_definitions_bp.route("/automation_definitions", methods=["GET"])
def list_automation_definitions():
    return jsonify(
        [definition.to_dict() for definition in AUTOMATION_DEFINITIONS.values()]
    )


@automation_definitions_bp.route("/automation_definitions/<key>", methods=["GET"])
def get_automation_definition(key):
    definition = get_definition(key)
    if definition is None:
        return jsonify({"error": "automation definition not found"}), 404
    return jsonify(definition.to_dict())
