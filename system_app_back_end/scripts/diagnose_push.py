#!/usr/bin/env python3
"""One-off diagnostic: run in the same environment as the cron job to see
exactly why dispatch() isn't sending. Not wired into any scheduled job."""
import os
import sys
from pathlib import Path
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
from app import app
from models import PushDevice
from areas.automations.services import push_notifications as pn

with app.app_context():
    key_path = os.environ.get("APNS_KEY_FILE", "")
    print("APNS_KEY_FILE env value:", repr(key_path))
    print("APNS_KEY_FILE exists on disk:", Path(key_path).exists() if key_path else False)
    print("configured():", pn.configured())
    devices = PushDevice.query.filter_by(active=True).all()
    print("active devices:", [(d.id, d.workspace_id, d.environment, d.token[:12] + "...") for d in devices])
    for d in devices:
        sections = pn.section_snapshot(d.workspace_id)
        print(f"device {d.id} sections:", sections)
        payload = pn.notification_payload(d, sections)
        print(f"device {d.id} payload:", payload)
        if payload is not None:
            try:
                with pn.APNsSender() as sender:
                    status, reason = sender(d, payload)
                    print(f"device {d.id} APNs response: status={status} reason={reason!r}")
            except Exception as exc:
                print(f"device {d.id} APNsSender raised: {exc!r}")
