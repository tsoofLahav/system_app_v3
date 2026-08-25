"""Everything an automation step can do, by name.

Same shape as the agent's own tools: arguments instead of a request, a dict
back with `error` when it cannot, and no commit — the runner commits once for
the whole series so a half-finished automation leaves nothing behind.

A new action is one function here and one entry in `STEP_SPECS`.
"""

from areas.automations.services.actions.ai import ai
from areas.automations.services.actions.files import (
    archive_files,
    create_file,
    fill_file,
)
from areas.automations.services.actions.tasks import unmark_tasks

ACTIONS = {
    "ai": ai,
    "create_file": create_file,
    "unmark_tasks": unmark_tasks,
    "archive_files": archive_files,
    "fill_file": fill_file,
}

__all__ = ["ACTIONS"]
