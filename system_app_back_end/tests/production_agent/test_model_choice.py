"""Which model runs, and how each kind of model is tuned.

The stored `agent_configs.model` used to default to a mini model nobody chose,
which quietly outranked the environment. Empty must mean "the deployment's
model" so a deploy can change it.
"""

from unittest.mock import MagicMock, patch

from areas.production_agent.services.openai_service import (
    create_response,
    is_reasoning_model,
)
from areas.production_agent.services.prompt import ensure_agent_config
from areas.production_agent.services.runner import _model_for_workspace
from config import OPENAI_MODEL


def _config(model: str) -> MagicMock:
    config = MagicMock()
    config.model = model
    return config


def test_blank_stored_model_falls_back_to_the_deployment():
    with patch(
        "areas.production_agent.services.runner.ensure_agent_config",
        return_value=_config(""),
    ):
        assert _model_for_workspace(1) == OPENAI_MODEL


def test_stored_model_is_a_deliberate_override():
    with patch(
        "areas.production_agent.services.runner.ensure_agent_config",
        return_value=_config("gpt-5.6-luna"),
    ):
        assert _model_for_workspace(1) == "gpt-5.6-luna"


def _ensure_with_stored_model(model: str) -> MagicMock:
    """Run `ensure_agent_config` against an existing row holding `model`."""
    config = _config(model)
    config.system_prompt = "Stored rules."
    query = MagicMock()
    query.filter_by.return_value.first.return_value = config
    with (
        patch("areas.production_agent.services.prompt.AgentConfig") as agent_config,
        patch("areas.production_agent.services.prompt.db"),
    ):
        agent_config.query = query
        ensure_agent_config(1)
    return config


def test_legacy_default_model_is_cleared_on_read():
    """No one chose gpt-4o-mini — it was a column default, so it is not an override."""
    assert _ensure_with_stored_model("gpt-4o-mini").model == ""


def test_a_real_override_survives():
    assert _ensure_with_stored_model("gpt-5.6-terra").model == "gpt-5.6-terra"


def test_is_reasoning_model():
    assert is_reasoning_model("gpt-5.6")
    assert is_reasoning_model("o3-mini")
    assert not is_reasoning_model("gpt-4o")
    assert not is_reasoning_model("")


def _sent_kwargs(model: str) -> dict:
    client = MagicMock()
    with patch(
        "areas.production_agent.services.openai_service._client",
        return_value=client,
    ):
        create_response(
            model=model,
            conversation_id="conv_1",
            instructions="be useful",
            tools=[],
            input="hello",
        )
    return client.responses.create.call_args.kwargs


def test_reasoning_model_gets_effort_and_no_temperature():
    kwargs = _sent_kwargs("gpt-5.6")
    assert kwargs["reasoning"] == {"effort": "low"}
    assert "temperature" not in kwargs


def test_chat_model_still_gets_temperature():
    kwargs = _sent_kwargs("gpt-4o")
    assert kwargs["temperature"] == 0.2
    assert "reasoning" not in kwargs
