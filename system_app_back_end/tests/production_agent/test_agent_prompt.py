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
    assert "What this system is" in text
    assert "How you work" in text
    assert "patch_file" in text
    assert "reference" in text
    # Bulky examples live in reference.md, not the standing prompt.
    assert "[BULLET_LIST]" not in text


def test_reference_sections():
    agent_text = load_reference_section("agent_text")
    assert "[BULLET_LIST]" in agent_text
    assert "[TASK_LIST" in agent_text
    assert "## tools" not in agent_text

    tools = load_reference_section("tools")
    assert "patch_file" in tools
    assert "move_text" in tools
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
