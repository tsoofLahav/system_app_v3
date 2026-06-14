from datetime import datetime

from flask import jsonify
from werkzeug.exceptions import HTTPException

from models import db


def parse_datetime(value):
    if value is None:
        return None
    if isinstance(value, datetime):
        return value
    if isinstance(value, str):
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    raise ValueError("Invalid datetime value")


def get_or_404(model, item_id):
    item = db.session.get(model, item_id)
    if item is None:
        from flask import abort

        abort(404, description=f"{model.__name__} not found")
    return item


def apply_updates(instance, data, allowed_fields, datetime_fields=None):
    datetime_fields = datetime_fields or set()
    for field in allowed_fields:
        if field not in data:
            continue
        value = data[field]
        if field in datetime_fields:
            value = parse_datetime(value)
        setattr(instance, field, value)


def register_error_handlers(app):
    @app.errorhandler(HTTPException)
    def handle_http_exception(error):
        response = jsonify({"error": error.description})
        response.status_code = error.code
        return response

    @app.errorhandler(ValueError)
    def handle_value_error(error):
        response = jsonify({"error": str(error)})
        response.status_code = 400
        return response

    @app.errorhandler(Exception)
    def handle_unexpected_error(error):
        db.session.rollback()
        response = jsonify({"error": "Internal server error"})
        response.status_code = 500
        return response
