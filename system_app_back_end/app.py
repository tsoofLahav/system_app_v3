import os

from flask import Flask, jsonify
from flask_cors import CORS

from config import DATABASE_URL, UPLOAD_FOLDER, resolve_upload_folder
from models import db
from areas import register_blueprints
from shared.helpers import register_error_handlers


def _ensure_upload_folder(app: Flask) -> None:
    folder = app.config["UPLOAD_FOLDER"]
    try:
        os.makedirs(folder, exist_ok=True)
        return
    except OSError:
        pass
    fallback = resolve_upload_folder()
    if fallback == folder:
        fallback = os.path.join(os.path.dirname(__file__), "uploads")
    os.makedirs(fallback, exist_ok=True)
    app.config["UPLOAD_FOLDER"] = fallback


def create_app():
    app = Flask(__name__)
    app.config["SQLALCHEMY_DATABASE_URI"] = DATABASE_URL
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
    app.config["SQLALCHEMY_ENGINE_OPTIONS"] = {
        "pool_pre_ping": True,
        "pool_recycle": 300,
    }
    app.config["UPLOAD_FOLDER"] = UPLOAD_FOLDER
    _ensure_upload_folder(app)

    CORS(app)
    db.init_app(app)
    register_blueprints(app)
    register_error_handlers(app)

    @app.route("/health", methods=["GET"])
    def health():
        return jsonify({"status": "ok"})

    @app.before_request
    def _sync_agent_prompt_once():
        # gunicorn workers sync in after_worker_fork; flask run uses this.
        if app.config.get("_PROMPT_BOOT_DONE"):
            return
        _sync_agent_prompt(app)

    return app


def _sync_agent_prompt(flask_app: Flask) -> None:
    from areas.production_agent.services.prompt import maybe_sync_prompts_on_boot

    maybe_sync_prompts_on_boot()
    flask_app.config["_PROMPT_BOOT_DONE"] = True


def after_worker_fork() -> None:
    """Open a fresh DB pool in this worker, then sync the agent prompt."""
    with app.app_context():
        db.session.remove()
        db.engine.dispose()
        _sync_agent_prompt(app)


app = create_app()


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port, debug=True)
