"""Tests for production agent prompt loading."""

from unittest.mock import MagicMock, patch

from areas.production_agent.services.prompt import (
    DEFAULT_TOOL_ALLOWLIST,
    load_prompt_file,
    load_reference_section,
    operational_suffix,
    system_prompt_for_workspace,
)


def test_load_prompt_file_is_short_standing_instructions():
    text = load_prompt_file()
    assert "## App structure" in text
    assert "## Tools" in text
    assert "## Agent text" in text
    assert "## Input" in text
    assert "list" in text
    assert "find_file" in text
    assert "find_object" in text
    assert "create_object" in text
    assert "patch_file" in text
    assert "one `patch_file` call" in text
    assert "[SPACER" in text
    assert "search_tasks" not in text
    assert "Scope is hard" not in text
    # Examples stay in reference.md — no code fences in the standing prompt.
    assert "```" not in text


def test_prompt_treats_scope_and_hints_as_context_only():
    """Where the user stands must never read as where the edit has to happen."""
    text = load_prompt_file()
    assert "not a target and not a boundary" in text
    assert '"This line", "this file", "this topic"' in text
    assert "any file in the workspace" in text


def test_prompt_says_searching_is_how_a_target_is_found():
    text = load_prompt_file()
    assert "search before you write" in text
    assert "find the right topic, file or object" in text


def test_default_tool_allowlist():
    assert "list" in DEFAULT_TOOL_ALLOWLIST
    assert "create_object" in DEFAULT_TOOL_ALLOWLIST
    assert "search" not in DEFAULT_TOOL_ALLOWLIST
    assert "search_tasks" not in DEFAULT_TOOL_ALLOWLIST


def test_reference_sections():
    agent_text = load_reference_section("agent_text")
    assert "[BULLET_LIST]" in agent_text
    assert "[TASK_LIST" in agent_text
    assert "## tools" not in agent_text

    tools = load_reference_section("tools")
    assert "patch_file" in tools
    assert "find_file" in tools
    assert "create_object" in tools
    assert "search_tasks" not in tools
    assert "[BULLET_LIST]" not in tools

    everything = load_reference_section("all")
    assert "[BULLET_LIST]" in everything
    assert "patch_file" in everything


def test_system_prompt_for_workspace_uses_db_and_suffix():
    config = MagicMock()
    config.system_prompt = "Stored production rules."
    with patch("areas.production_agent.services.prompt.ensure_agent_config", return_value=config):
        prompt = system_prompt_for_workspace(1)
    assert "Stored production rules." in prompt
    assert operational_suffix() in prompt
    assert "reference" in prompt
