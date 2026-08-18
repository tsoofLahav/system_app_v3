"""The step vocabulary: what an automation can be asked to do, and its shape.

A step is `{"kind": …}` plus that kind's parameters. Validation lives here as a
pure function so a bad automation is refused when it is saved rather than at
2am when it fires — and so the rules can be read without a database.

Adding a kind is two things: an entry in `STEP_SPECS` and a function in
`actions/`. A test holds those two lists to the same length.
"""

from __future__ import annotations

from datetime import datetime

APPLY_MODES = ("review", "direct_apply", "notify_only")

# kind -> the keys it keeps. Anything else the client sends is dropped, so a
# step never accumulates fields nobody reads.
STEP_SPECS: dict[str, tuple[str, ...]] = {
    "ai": ("action_id", "prompt", "apply_mode"),
    "create_file": ("name", "topic_id"),
    "unmark_tasks": ("task_list_id",),
    "archive_files": ("file_ids", "older_than_days"),
}

STEP_KINDS = tuple(STEP_SPECS)


class StepError(ValueError):
    """A step that cannot run, caught at save time."""


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise StepError(message)


def _validate_one(step: dict, *, position: int) -> dict:
    _require(isinstance(step, dict), f"step {position} is not an object")
    kind = str(step.get("kind") or "").strip()
    _require(kind in STEP_SPECS, f"step {position}: unknown kind {kind!r}")

    kept = {"kind": kind}
    for key in STEP_SPECS[kind]:
        if step.get(key) not in (None, ""):
            kept[key] = step[key]

    if kind == "ai":
        _require(
            bool(kept.get("prompt")) or kept.get("action_id") is not None,
            f"step {position}: an AI step needs a prompt or a saved action",
        )
        mode = kept.get("apply_mode")
        _require(
            mode is None or mode in APPLY_MODES,
            f"step {position}: apply_mode must be one of {', '.join(APPLY_MODES)}",
        )
    elif kind == "create_file":
        _require(
            bool(str(kept.get("name") or "").strip()),
            f"step {position}: a file needs a name",
        )
    # archive_files with no extra fields means every live file in scope.

    return kept


def validate_steps(raw) -> list[dict]:
    """Normalise a client's steps, or raise `StepError` naming the bad one."""
    _require(isinstance(raw, list), "steps must be a list")
    return [_validate_one(step, position=i + 1) for i, step in enumerate(raw)]


def expand_name_tokens(name: str, *, now: datetime) -> str:
    """`Week of {date}` → `Week of 2026-08-18`.

    A file an automation makes every week needs a name that moves with it,
    and the alternative is asking the model to name a file it never reads.
    """
    return (
        (name or "")
        .replace("{date}", now.strftime("%Y-%m-%d"))
        .replace("{weekday}", now.strftime("%A"))
        .replace("{month}", now.strftime("%B"))
        .replace("{year}", now.strftime("%Y"))
    )
