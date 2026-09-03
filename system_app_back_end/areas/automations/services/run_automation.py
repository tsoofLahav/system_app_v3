"""Run one automation: resolve its scope, then walk its steps in order.

Steps stop at the first failure. An automation is a sequence someone wrote on
purpose — "unmark the list, then ask the agent to summarise it" reads wrong if
the summary runs after the unmark failed. What did happen is kept: the runner
commits, so earlier steps stand, and the run record says where it stopped.
"""

from __future__ import annotations

from datetime import datetime

from models import Automation, AutomationRun, db
from areas.automations.services.actions import ACTIONS
from areas.automations.services.automation_schedule import wall_clock
from areas.automations.services.scope import resolve_scope


def run_steps(
    *,
    workspace_id: int,
    scope: dict | None,
    steps: list[dict],
    now: datetime | None = None,
    user_input: dict | None = None,
) -> dict:
    """Execute a series and describe what happened, step by step."""
    now = now or wall_clock(datetime.utcnow())
    resolved = resolve_scope(scope, workspace_id=workspace_id)
    records: list[dict] = []

    for position, step in enumerate(steps or [], 1):
        kind = str(step.get("kind") or "")
        action = ACTIONS.get(kind)
        if action is None:
            records.append({"step": position, "kind": kind, "error": "unknown step"})
            break

        params = {k: v for k, v in step.items() if k != "kind"}
        if user_input:
            params = {**params, "user_input": user_input}
        try:
            outcome = action(
                workspace_id=workspace_id,
                resolved_scope=resolved,
                params=params,
                now=now,
            )
        except Exception as error:  # a step must not take the whole job down
            outcome = {"error": str(error)}

        records.append({"step": position, "kind": kind, **outcome})
        if outcome.get("error"):
            break

    failed = next((r for r in records if r.get("error")), None)
    return {
        "status": "failed" if failed else "ok",
        "error": failed.get("error") if failed else None,
        "steps": records,
        "scope": resolved,
    }


def run_automation(
    automation: Automation,
    *,
    trigger_source: str,
    user_input: dict | None = None,
) -> AutomationRun:
    """Run it and record it. The caller commits."""
    from areas.automations.services.section_windows import (
        KIND_SECTION_WINDOW,
        complete_review_if_clear,
        mark_input_done,
    )

    run = AutomationRun(
        automation_id=automation.id,
        status="running",
        trigger_source=trigger_source,
        event_context={"user_input": user_input} if user_input else {},
    )
    db.session.add(run)
    db.session.flush()

    now_utc = datetime.utcnow()
    now = wall_clock(now_utc, automation.timezone)
    if (automation.kind or "standard") == KIND_SECTION_WINDOW:
        result = {"status": "ok", "steps": [], "scope": {}}
    else:
        try:
            result = run_steps(
                workspace_id=automation.workspace_id,
                scope=automation.scope,
                steps=automation.steps or [],
                now=now,
                user_input=user_input or automation.pending_user_input,
            )
        except Exception as error:
            result = {"status": "failed", "error": str(error), "steps": []}

    run.status = "completed" if result.get("status") == "ok" else "failed"
    run.result = result
    run.error = result.get("error")
    run.finished_at = datetime.utcnow()
    automation.last_run_at = run.finished_at
    if (automation.kind or "standard") != KIND_SECTION_WINDOW and run.status == "completed":
        mark_input_done(automation)
        complete_review_if_clear(automation)
    return run
