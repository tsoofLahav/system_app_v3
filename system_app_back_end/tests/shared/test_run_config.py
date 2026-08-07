"""Defaults must stay imported — not re-hardcoded at call sites."""

from shared.run_config import (
    DEFAULT_AUTOMATION_APPLY_MODE,
    DEFAULT_MANUAL_APPLY_MODE,
)
from areas.production_agent.services.write_tools import resolve_write_mode


def test_apply_mode_defaults_are_known_modes():
    allowed = {"review", "direct_apply", "notify_only"}
    assert DEFAULT_MANUAL_APPLY_MODE in allowed
    assert DEFAULT_AUTOMATION_APPLY_MODE in allowed


def test_resolve_write_mode_empty_uses_manual_default():
    assert resolve_write_mode("patch_file", "") == DEFAULT_MANUAL_APPLY_MODE
