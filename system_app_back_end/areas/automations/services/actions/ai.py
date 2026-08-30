"""The AI step: hand a prompt to the same agent a typed prompt reaches.

The prompt is either written into the automation or borrowed from a saved AI
action, so a prompt the user already trusts has one home. `apply_mode` on the
step wins over the action's own, because a button pressed while watching and a
job running at 2am do not deserve the same trust.
"""

from __future__ import annotations

from datetime import datetime

from models import AiAction, db
from shared.run_config import DEFAULT_AUTOMATION_APPLY_MODE
from areas.production_agent.services.runner import run_agent


def _prompt_and_mode(params: dict) -> tuple[str, str] | dict:
    action_id = params.get("action_id")
    if action_id is None:
        return (params.get("prompt") or "").strip(), (
            params.get("apply_mode") or DEFAULT_AUTOMATION_APPLY_MODE
        )

    action = db.session.get(AiAction, int(action_id))
    if action is None:
        return {"error": f"saved action {action_id} no longer exists"}
    return (action.prompt or "").strip(), (
        params.get("apply_mode") or action.apply_mode or DEFAULT_AUTOMATION_APPLY_MODE
    )


def ai(*, workspace_id: int, resolved_scope: dict, params: dict, now: datetime):
    resolved = _prompt_and_mode(params)
    if isinstance(resolved, dict):
        return resolved
    prompt, apply_mode = resolved
    if not prompt:
        return {"error": "the AI step has no prompt"}

    from areas.automations.services.section_windows import format_user_input_for_prompt

    user_note = format_user_input_for_prompt(params.get("user_input"))
    if user_note:
        prompt = f"{prompt}\n\nUser input:\n{user_note}"

    result = run_agent(
        prompt=prompt,
        workspace_id=workspace_id,
        scope=resolved_scope,
        apply_mode=apply_mode,
        hints={"today": now.strftime("%Y-%m-%d"), "weekday": now.strftime("%A")},
    )
    if result.get("status") != "ok":
        return {"error": result.get("error") or "the agent run failed", "agent": result}
    return {
        "ok": True,
        "summary": result.get("summary") or "",
        "applied": bool(result.get("applied")),
        "pending_review_ids": result.get("pending_review_ids") or [],
        "agent": result,
    }
