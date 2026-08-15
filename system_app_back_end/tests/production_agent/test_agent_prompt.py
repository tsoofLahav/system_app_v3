"""Tests for production agent prompt loading."""

from unittest.mock import MagicMock, patch

from areas.production_agent.services.prompt import (
    load_prompt_file,
    load_reference_section,
    operational_suffix,
    system_prompt_for_workspace,
)


def test_load_prompt_file_is_short_standing_instructions():
    text = load_prompt_file()
    assert "Agent text" in text
    assert "patch_file" in text
    assert "add" in text
    assert "reference" in text
    # Examples stay in reference.md — no code fences in the standing prompt.
    assert "```" not in text


def test_reference_sections():
    agent_text = load_reference_section("agent_text")
    assert "[BULLET_LIST]" in agent_text
    assert "[TASK_LIST" in agent_text
    assert "## tools" not in agent_text

    tools = load_reference_section("tools")
    assert "patch_file" in tools
    assert '"op": "add"' in tools or "add |" in tools or '"op"' in tools
    assert "move_text" not in tools
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
