from flask import Blueprint, jsonify, request

from services.ai_tools import run_tool

ai_bp = Blueprint("ai", __name__)

ALLOWED_TOOLS = {
    "consult",
    "summarize_to_doc",
    "smart_list",
    "create_image",
    "create_graph",
    "review",
}


@ai_bp.route("/ai/run", methods=["POST"])
def ai_run():
    data = request.get_json(silent=True) or {}
    tool = data.get("tool")
    topic_id = data.get("topic_id")
    context = data.get("context") or {}
    locale = data.get("locale") or "en"

    if tool not in ALLOWED_TOOLS:
        return jsonify({"error": f"Invalid tool: {tool}"}), 400
    if not topic_id:
        return jsonify({"error": "topic_id is required"}), 400

    try:
        result = run_tool(tool, int(topic_id), context, locale=locale)
        return jsonify(result)
    except RuntimeError as e:
        return jsonify({"error": str(e)}), 503
    except ValueError as e:
        return jsonify({"error": str(e)}), 400
    except Exception as e:
        return jsonify({"error": str(e)}), 500
