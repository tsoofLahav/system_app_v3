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


def _upload_folder() -> str:
    try:
        return current_app.config["UPLOAD_FOLDER"]
    except RuntimeError:
        from config import UPLOAD_FOLDER

        return UPLOAD_FOLDER


def store_image_bytes(
    data: bytes,
    original_name: str = "generated.png",
    mimetype: str | None = "image/png",
) -> str:
    """Write image bytes to the upload folder. Returns ``/images/<filename>``."""
    upload_folder = _upload_folder()
    os.makedirs(upload_folder, exist_ok=True)
    filename = _safe_stored_name(original_name, mimetype)
    dest = os.path.join(upload_folder, filename)
    with open(dest, "wb") as handle:
        handle.write(data)
    return f"/images/{filename}"


@upload_bp.route("/upload-image", methods=["POST"])
def upload_image():
    if "image" not in request.files:
        return jsonify({"error": "No image file provided"}), 400

    file = request.files["image"]
    if not file or not file.filename:
        return jsonify({"error": "No image file selected"}), 400

    if not allowed_file(file.filename):
        return jsonify({"error": "File type not allowed"}), 400

    try:
        image_path = store_image_bytes(
            file.read(),
            original_name=file.filename,
            mimetype=file.mimetype,
        )
    except OSError as exc:
        logger.exception("Failed to save uploaded image")
        return jsonify({"error": f"Could not save image: {exc}"}), 500

    filename = image_path.rsplit("/", 1)[-1]
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
