import os
import uuid

from flask import Blueprint, current_app, jsonify, request, send_from_directory
from werkzeug.utils import secure_filename

upload_bp = Blueprint("upload", __name__)

ALLOWED_EXTENSIONS = {"png", "jpg", "jpeg", "gif", "webp", "svg"}


def allowed_file(filename):
    return "." in filename and filename.rsplit(".", 1)[1].lower() in ALLOWED_EXTENSIONS


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
    os.makedirs(upload_folder, exist_ok=True)

    original = secure_filename(file.filename)
    name, ext = os.path.splitext(original)
    filename = f"{name}_{uuid.uuid4().hex[:8]}{ext}"
    file.save(os.path.join(upload_folder, filename))

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
