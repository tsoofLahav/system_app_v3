"""Production agent system prompt — loaded from agent_configs in the database."""

from __future__ import annotations

from pathlib import Path

from models import AgentConfig, db

DEFAULT_CONFIG_NAME = "default"
DEFAULT_TOOL_ALLOWLIST = ["search", "open_file", "update_file", "search_tasks"]
REPO_ROOT = Path(__file__).resolve().parents[4]
PROMPT_FILE = REPO_ROOT / "content" / "production_agent" / "system_prompt.md"


def load_prompt_file() -> str:
    return PROMPT_FILE.read_text(encoding="utf-8")


def operational_suffix() -> str:
    return (
        "\n\nYou are the system_app production document assistant. "
        "The first user message is prompt + hard scope (+ tiny hints) only — "
        "never assume file bodies are already loaded. "
        "Use tools to search and open_file before editing. "
        "Never invent file or object ids; only use ids returned by tools or listed in scope. "
        "Archived files are readable via open_file but never writable. "
        "When updating a file, call update_file with the FULL new document_text. "
        "Preserve every existing embed object_id; never omit fenced object blocks. "
        "When finished, reply with a short plain-text summary (no JSON wrapper)."
    )


def ensure_agent_config(workspace_id: int, *, seed_from_file: bool = True) -> AgentConfig:
    """Ensure the default agent_configs row exists for a workspace."""
    config = AgentConfig.query.filter_by(
        workspace_id=workspace_id,
        name=DEFAULT_CONFIG_NAME,
    ).first()
    if config is None:
        config = AgentConfig(
            workspace_id=workspace_id,
            name=DEFAULT_CONFIG_NAME,
            system_prompt=load_prompt_file() if seed_from_file else "",
            tool_allowlist=list(DEFAULT_TOOL_ALLOWLIST),
        )
        db.session.add(config)
        db.session.flush()
        return config

    if seed_from_file and not (config.system_prompt or "").strip():
        config.system_prompt = load_prompt_file()
        db.session.flush()
    return config


def system_prompt_for_workspace(workspace_id: int) -> str:
    config = ensure_agent_config(workspace_id)
    body = (config.system_prompt or "").strip() or load_prompt_file()
    return body + operational_suffix()


def sync_prompt_from_file(workspace_id: int, *, overwrite: bool = False) -> AgentConfig:
    """Copy content/production_agent/system_prompt.md into agent_configs.system_prompt."""
    config = ensure_agent_config(workspace_id, seed_from_file=False)
    if overwrite or not (config.system_prompt or "").strip():
        config.system_prompt = load_prompt_file()
        db.session.flush()
    return config
