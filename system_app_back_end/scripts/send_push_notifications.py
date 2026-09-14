#!/usr/bin/env python3
"""Run every minute, separately from AI automations, using the same database."""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
from app import app
from areas.automations.services.push_notifications import dispatch

if __name__ == "__main__":
    with app.app_context():
        print(f"[push] accepted={dispatch()}", flush=True)
