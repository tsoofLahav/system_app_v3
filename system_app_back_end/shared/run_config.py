"""Agent / automation run defaults.

Single source of truth for apply-mode strings. Call sites import these —
do not hardcode ``"review"`` / ``"direct_apply"`` / ``"notify_only"`` as
fallbacks elsewhere.
"""

# Manual consult when `apply_mode` is omitted on POST /agent/run.
# Consult UI normally sends review | direct_apply explicitly.
DEFAULT_MANUAL_APPLY_MODE = "direct_apply"

# New automations (API create + DB column default) when apply_mode omitted.
DEFAULT_AUTOMATION_APPLY_MODE = "review"
