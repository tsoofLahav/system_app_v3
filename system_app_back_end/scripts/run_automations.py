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
from areas.automations.services.automation_schedule import (
    normalize_stored_timezone,
    plan_tick,
)
from areas.automations.services.run_automation import run_automation
from areas.automations.services.section_windows import (
    KIND_SECTION_WINDOW,
    KIND_STANDARD,
    tick_section_window,
)
from areas.objects.services.task_ops import activate_due_pending_tasks
from config import openai_api_key

logger = logging.getLogger(__name__)


def _log(message: str) -> None:
    # Render captures stdout. `logger.info` is silent unless Flask configured it.
    print(message, flush=True)
    logger.info(message)


def tick(now: datetime | None = None) -> int:
    """Returns how many automations ran."""
    now = now or datetime.now(dt_timezone.utc)
    try:
        activated = activate_due_pending_tasks(now=now)
        if activated:
            db.session.commit()
            _log(f"[automations] pending→active count={len(activated)}")
    except Exception:
        logger.exception("pending activate failed")
        print("[automations] pending activate failed", flush=True)
        db.session.rollback()

    rows = Automation.query.filter(
        Automation.enabled.is_(True),
        Automation.schedule.isnot(None),
        Automation.schedule != "",
    ).all()

    openai_names = sorted(k for k in os.environ if "OPENAI" in k.upper())
    _log(
        f"[automations] tick {now.isoformat()} rows={len(rows)} "
        f"openai_key={'yes' if openai_api_key() else 'no'} "
        f"openai_env={openai_names or '[]'}"
    )
    ran = 0
    for row in rows:
        try:
            if normalize_stored_timezone(row):
                _log(
                    f"[automations] id={row.id} tz UTC→Asia/Jerusalem "
                    f"(re-arm next_run_at)"
                )
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
            kind = row.kind or KIND_STANDARD
            if kind == KIND_SECTION_WINDOW:
                tick_section_window(
                    row, now=now, action=action, planned=planned_next
                )
                if action == "run":
                    ran += 1
                    _log(f"[automations] id={row.id} section-window {action}")
                db.session.commit()
                continue

            # Locked to a section window: the clock is that window's, not this row's.
            if row.view_id and row.section_key:
                window = Automation.query.filter_by(
                    kind=KIND_SECTION_WINDOW,
                    view_id=row.view_id,
                    section_key=row.section_key,
                ).first()
                if window is None or not window.enabled:
                    _log(
                        f"[automations] id={row.id} skip locked "
                        f"(section window off)"
                    )
                    if action == "arm":
                        row.next_run_at = planned_next
                        db.session.commit()
                    continue
                if action == "arm":
                    row.next_run_at = planned_next
                    db.session.commit()
                continue

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
