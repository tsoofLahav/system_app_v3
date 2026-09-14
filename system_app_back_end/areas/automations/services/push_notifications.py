"""APNs delivery from committed section state; no phone process required.

Last accepted state is durable. Failed deliveries retry on the next minute tick,
recomputing current state instead of sending an obsolete queued badge. A row lock
serializes delivery and profile changes across workers. No network call from task
writes; this dispatcher runs independently of slow AI work.
"""
from datetime import datetime
import logging
import os
import time
from pathlib import Path

from models import Automation, PushDevice, db
from .section_windows import attention_for_window

logger = logging.getLogger(__name__)


def configured():
    return os.environ.get("APNS_ENABLED", "").lower() == "true" and all(
        os.environ.get(key) for key in ("APNS_KEY_ID", "APNS_TEAM_ID", "APNS_TOPIC", "APNS_KEY_FILE")
    )


def section_snapshot(workspace_id, now=None):
    now = now or datetime.utcnow()
    rows = Automation.query.filter_by(workspace_id=workspace_id,
                                       kind="section_window", enabled=True).order_by(Automation.id).all()
    return [{"key": f"{row.id}:{row.window_opened_at.isoformat()}",
             "title": row.name, "title_he": row.name_he or row.name}
            for row in rows if attention_for_window(row, now)]


def notification_payload(device, sections):
    keys = [item["key"] for item in sections]
    new = [item for item in sections if item["key"] not in (device.last_keys or [])]
    if keys == (device.last_keys or []) and len(keys) == device.last_badge:
        return None
    aps = {"badge": len(keys), "thread-id": "section_windows"}
    if new:
        hebrew = device.language == "he"
        aps["alert"] = {
            "title": (new[0]["title_he"] if hebrew else new[0]["title"])[:180],
            "body": "יש משימות שממתינות לך" if hebrew else "You have tasks waiting for you",
        }
    return {"aps": aps, "workspace_id": device.workspace_id,
            "kind": "section_windows"}


class APNsSender:
    def __enter__(self):
        import httpx
        import jwt
        self.client = httpx.Client(http2=True, timeout=10)
        self.authorization = jwt.encode(
            {"iss": os.environ["APNS_TEAM_ID"], "iat": int(time.time())},
            Path(os.environ["APNS_KEY_FILE"]).read_text(), algorithm="ES256",
            headers={"kid": os.environ["APNS_KEY_ID"]},
        )
        return self

    def __exit__(self, *args):
        self.client.close()

    def __call__(self, device, payload):
        host = "api.sandbox.push.apple.com" if device.environment == "sandbox" else "api.push.apple.com"
        response = self.client.post(f"https://{host}/3/device/{device.token}", json=payload,
            headers={"authorization": f"bearer {self.authorization}",
                     "apns-topic": os.environ["APNS_TOPIC"], "apns-push-type": "alert",
                     "apns-priority": "10", "apns-expiration": "0",
                     "apns-collapse-id": "section-attention"})
        reason = ""
        if response.status_code != 200:
            try:
                reason = response.json().get("reason", "")
            except ValueError:
                pass
        return response.status_code, reason


def dispatch(sender=None):
    if not configured():
        return 0
    if sender is None:
        with APNsSender() as connection:
            return dispatch(connection)
    sent = 0
    ids = [row.id for row in PushDevice.query.filter_by(active=True).all()]
    db.session.commit()
    for device_id in ids:
        try:
            device = PushDevice.query.filter_by(id=device_id, active=True).with_for_update(skip_locked=True).first()
            if device is None:
                db.session.rollback()
                continue
            sections = section_snapshot(device.workspace_id)
            payload = notification_payload(device, sections)
            if payload is not None:
                status, reason = sender(device, payload)
                if status == 200:
                    device.last_keys = [item["key"] for item in sections]
                    device.last_badge = len(sections)
                    sent += 1
                elif status == 410 or (status == 400 and reason in ("BadDeviceToken", "DeviceTokenNotForTopic")):
                    device.active = False
                else:
                    logger.warning("APNs delivery failed device=%s status=%s reason=%s", device.id, status, reason)
            db.session.commit()
        except Exception:
            db.session.rollback()
            logger.exception("APNs delivery failed device=%s", device_id)
    return sent
