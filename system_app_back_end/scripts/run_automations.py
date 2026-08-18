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


def _log(message: str) -> None:
    # Render captures stdout. `logger.info` is silent unless Flask configured it.
    print(message, flush=True)
    logger.info(message)


def tick(now: datetime | None = None) -> int:
    """Returns how many automations ran."""
    now = now or datetime.now(dt_timezone.utc)
    rows = Automation.query.filter(
        Automation.enabled.is_(True),
        Automation.schedule.isnot(None),
        Automation.schedule != "",
    ).all()

    _log(f"[automations] tick {now.isoformat()} rows={len(rows)}")
    ran = 0
    for row in rows:
        try:
            action, planned_next = plan_tick(
                schedule=row.schedule,
                timezone=row.timezone,
                now_utc=now,
                next_run_at=row.next_run_at,
            )
            _log(
                f"[automations] id={row.id} {action} "
                f"schedule={row.schedule!r} tz={row.timezone} "
                f"next_run_at={row.next_run_at} -> {planned_next}"
            )
            if action == "skip":
                continue

            row.next_run_at = planned_next
            if action == "run":
                run = run_automation(row, trigger_source="schedule")
                ran += 1
                _log(
                    f"[automations] id={row.id} finished: {run.status} "
                    f"({run.error or 'ok'})"
                )
            db.session.commit()
        except Exception:
            logger.exception("automation %s tick failed", row.id)
            print(f"[automations] id={row.id} tick failed", flush=True)
            db.session.rollback()
    return ran


def main() -> int:
    with app.app_context():
        tick()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
