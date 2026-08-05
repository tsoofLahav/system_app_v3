"""Tests for production agent prompt loading."""

from unittest.mock import MagicMock, patch

from areas.production_agent.services.prompt import (
    load_prompt_file,
    operational_suffix,
    system_prompt_for_workspace,
)


def test_load_prompt_file_contains_agent_format():
    text = load_prompt_file()
    assert "[BULLET_LIST]" in text
    assert "document_json" in text


def test_system_prompt_for_workspace_uses_db_and_suffix():
    config = MagicMock()
    config.system_prompt = "Stored production rules."
    with patch("areas.production_agent.services.prompt.ensure_agent_config", return_value=config):
        prompt = system_prompt_for_workspace(1)
    assert "Stored production rules." in prompt
    assert "open_file" in prompt
    assert "Links" in prompt
    assert "Never invent file or object ids" in prompt
    assert operational_suffix() in prompt
