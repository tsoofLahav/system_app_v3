#!/usr/bin/env python3
"""Every minute: run the automations that are due, and only those.

This used to load every enabled row and run it, which meant a saved AI action
— same table back then — fired 1,440 times a day. Actions live in their own
table now, and what is left here consults the schedule.
"""

from __future__ import annotations

import logging
import os
import sys
from datetime import datetime, timezone as dt_timezone

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from app import app
from models import Automation, db
from areas.automations.services.automation_schedule import plan_tick
from areas.automations.services.run_automation import run_automation

logger = logging.getLogger(__name__)


def tick(now: datetime | None = None) -> int:
    """Returns how many automations ran."""
    now = now or datetime.now(dt_timezone.utc)
    rows = Automation.query.filter(
        Automation.enabled.is_(True),
        Automation.schedule.isnot(None),
    ).all()

    ran = 0
    for row in rows:
        try:
            action, next_run_at = plan_tick(
                schedule=row.schedule,
                timezone=row.timezone,
                now_utc=now,
                next_run_at=row.next_run_at,
            )
            if action == "skip":
                continue

            row.next_run_at = next_run_at
            if action == "run":
                run = run_automation(row, trigger_source="schedule")
                ran += 1
                logger.info(
                    "automation %s finished: %s (%s)",
                    row.id,
                    run.status,
                    run.error or "ok",
                )
            db.session.commit()
        except Exception:
            logger.exception("automation %s tick failed", row.id)
            db.session.rollback()
    return ran


def main() -> int:
    with app.app_context():
        tick()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
