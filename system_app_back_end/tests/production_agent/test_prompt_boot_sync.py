"""Boot-time prompt sync gating."""

from areas.production_agent.services.prompt import should_sync_prompt_on_boot


def test_boot_sync_default_off_locally(monkeypatch):
    monkeypatch.delenv("RENDER", raising=False)
    monkeypatch.delenv("SYNC_AGENT_PROMPT_ON_DEPLOY", raising=False)
    assert should_sync_prompt_on_boot() is False


def test_boot_sync_on_render(monkeypatch):
    monkeypatch.setenv("RENDER", "true")
    monkeypatch.delenv("SYNC_AGENT_PROMPT_ON_DEPLOY", raising=False)
    assert should_sync_prompt_on_boot() is True


def test_boot_sync_opt_out_on_render(monkeypatch):
    monkeypatch.setenv("RENDER", "true")
    monkeypatch.setenv("SYNC_AGENT_PROMPT_ON_DEPLOY", "0")
    assert should_sync_prompt_on_boot() is False


def test_boot_sync_opt_in_locally(monkeypatch):
    monkeypatch.delenv("RENDER", raising=False)
    monkeypatch.setenv("SYNC_AGENT_PROMPT_ON_DEPLOY", "1")
    assert should_sync_prompt_on_boot() is True
