"""Installation registration for the currently selected presentation profile."""
from datetime import datetime
import re
from uuid import UUID
from flask import Blueprint, abort, jsonify, request
from models import PushDevice, db
from shared.bootstrap import default_workspace_id
from ..services.push_notifications import configured, section_snapshot

push_devices_bp = Blueprint("push_devices", __name__)


@push_devices_bp.post("/push-devices/register")
def register_device():
    # Feature gate permits deployment before manually applying migration 027.
    if not configured():
        return jsonify({"enabled": False})
    body = request.get_json() or {}
    try:
        installation = str(UUID(str(body.get("installation_id", ""))))
    except ValueError:
        abort(400, description="Invalid installation id")
    token = str(body.get("token", "")).lower()
    environment = body.get("environment")
    if not re.fullmatch(r"[0-9a-f]{32,512}", token) or environment not in ("sandbox", "production"):
        abort(400, description="Invalid push registration")
    wid = default_workspace_id()
    if wid is None:
        abort(400, description="Workspace is not ready")
    # Installation identity is deliberately global so profile selection moves it.
    device = PushDevice.query.filter_by(installation_id=installation).with_for_update().first()
    if device is None:
        device = PushDevice(installation_id=installation)
    if (device.workspace_id, device.token, device.environment) != (wid, token, environment):
        current = section_snapshot(wid)
        device.last_keys = [item["key"] for item in current]
        device.last_badge = -1
    # A restored installation may carry a new installation UUID with the same token.
    duplicates = PushDevice.query.filter(PushDevice.token == token,
        PushDevice.environment == environment, PushDevice.installation_id != installation).all()
    for other in duplicates:
        other.active = False
    device.workspace_id = wid
    device.token = token
    device.environment = environment
    device.language = "he" if body.get("language") == "he" else "en"
    device.active = body.get("authorized", True) is True
    device.updated_at = datetime.utcnow()
    db.session.add(device)
    db.session.commit()
    return jsonify({"enabled": device.active})
