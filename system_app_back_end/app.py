import os

from flask import Flask, jsonify
from flask_cors import CORS

from config import DATABASE_URL, UPLOAD_FOLDER, resolve_upload_folder
from models import db
from routes import register_blueprints
from routes.helpers import register_error_handlers


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
    app.config["UPLOAD_FOLDER"] = UPLOAD_FOLDER
    _ensure_upload_folder(app)

    CORS(app)
    db.init_app(app)
    register_blueprints(app)
    register_error_handlers(app)

    @app.route("/health", methods=["GET"])
    def health():
        return jsonify({"status": "ok"})

    return app


app = create_app()


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port, debug=True)
