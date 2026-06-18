import logging
import mimetypes
import os
import uuid

from flask import Blueprint, current_app, jsonify, request, send_from_directory
from werkzeug.utils import secure_filename

upload_bp = Blueprint("upload", __name__)
logger = logging.getLogger(__name__)

ALLOWED_EXTENSIONS = {"png", "jpg", "jpeg", "gif", "webp", "svg"}


def allowed_file(filename: str) -> bool:
    return "." in filename and filename.rsplit(".", 1)[1].lower() in ALLOWED_EXTENSIONS


def _extension_for_upload(original_name: str, mimetype: str | None) -> str:
    _, ext = os.path.splitext(original_name)
    if ext:
        return ext.lower()
    guessed = mimetypes.guess_extension(mimetype or "") or ""
    if guessed == ".jpe":
        guessed = ".jpg"
    return guessed or ".png"


def _safe_stored_name(original_name: str, mimetype: str | None) -> str:
    cleaned = secure_filename(original_name)
    name, ext = os.path.splitext(cleaned)
    if not ext:
        ext = _extension_for_upload(original_name, mimetype)
    if not name:
        name = "image"
    return f"{name}_{uuid.uuid4().hex[:8]}{ext}"


@upload_bp.route("/upload-image", methods=["POST"])
def upload_image():
    if "image" not in request.files:
        return jsonify({"error": "No image file provided"}), 400

    file = request.files["image"]
    if not file or not file.filename:
        return jsonify({"error": "No image file selected"}), 400

    if not allowed_file(file.filename):
        return jsonify({"error": "File type not allowed"}), 400

    upload_folder = current_app.config["UPLOAD_FOLDER"]
    try:
        os.makedirs(upload_folder, exist_ok=True)
        filename = _safe_stored_name(file.filename, file.mimetype)
        dest = os.path.join(upload_folder, filename)
        file.save(dest)
    except OSError as exc:
        logger.exception("Failed to save uploaded image to %s", upload_folder)
        return jsonify({"error": f"Could not save image: {exc}"}), 500

    image_path = f"/images/{filename}"
    return jsonify(
        {
            "filename": filename,
            "image_path": image_path,
            "url": image_path,
        }
    ), 201


@upload_bp.route("/images/<filename>")
def serve_image(filename):
    return send_from_directory(current_app.config["UPLOAD_FOLDER"], filename)
