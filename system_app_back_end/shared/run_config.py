"""Agent / automation run defaults.

Single source of truth for apply-mode strings. Call sites import these —
do not hardcode ``"review"`` / ``"direct_apply"`` / ``"notify_only"`` as
fallbacks elsewhere.
"""

# Manual consult (POST /agent/run when apply_mode omitted).
# Temporary direct_apply until the real lookalike diff UI (plan step 6).
DEFAULT_MANUAL_APPLY_MODE = "direct_apply"

# New automations (API create + DB column default) when apply_mode omitted.
DEFAULT_AUTOMATION_APPLY_MODE = "review"
