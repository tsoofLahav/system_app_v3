#!/usr/bin/env python3
"""Run due automations by calling the v2 agent pipeline."""

from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from app import app
from models import Automation, AutomationRun, db
from services.agent.runner import run_agent


def main() -> int:
    with app.app_context():
        rows = Automation.query.filter_by(enabled=True).all()
        for row in rows:
            run = AutomationRun(
                automation_id=row.id,
                status="running",
                trigger_source="schedule",
            )
            db.session.add(run)
            db.session.flush()
            result = run_agent(
                prompt=row.prompt,
                workspace_id=row.workspace_id,
                scope=row.scope or {},
                apply_mode=row.apply_mode,
            )
            run.status = "completed" if result.get("status") == "ok" else "failed"
            run.result = result
            if result.get("status") != "ok":
                run.error = result.get("error")
            db.session.commit()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
