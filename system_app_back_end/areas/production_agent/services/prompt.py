"""Production agent system prompt — loaded from agent_configs in the database."""

from __future__ import annotations

import logging
import os
from pathlib import Path

from models import AgentConfig, Workspace, db

DEFAULT_CONFIG_NAME = "default"
DEFAULT_TOOL_ALLOWLIST = [
    "search",
    "open_file",
    "patch_file",
    "move_text",
    "rewrite_file",
    "search_tasks",
]
_HERE = Path(__file__).resolve()
# Monorepo root (…/system_app) when services live under system_app_back_end/areas/…
REPO_ROOT = _HERE.parents[4]
PROMPT_FILE = REPO_ROOT / "content" / "production_agent" / "system_prompt.md"
# Fallback if Root Directory packaging ever omits the sibling content/ tree.
_BACKEND_PROMPT_FILE = (
    _HERE.parents[3] / "content" / "production_agent" / "system_prompt.md"
)

logger = logging.getLogger(__name__)


def resolve_prompt_file() -> Path:
    if PROMPT_FILE.is_file():
        return PROMPT_FILE
    if _BACKEND_PROMPT_FILE.is_file():
        return _BACKEND_PROMPT_FILE
    return PROMPT_FILE


def load_prompt_file() -> str:
    path = resolve_prompt_file()
    return path.read_text(encoding="utf-8")


def operational_suffix() -> str:
    return (
        "\n\nYou are the system_app production document assistant. "
        "The first user message is prompt + hard scope (+ tiny hints) only — "
        "never assume file bodies are already loaded. "
        "Use tools to search and open_file before editing. "
        "open_file returns document_plain (fenced agent text) and optional "
        "object_extras. For info objects, object_extras may include title and "
        "Links (each link: id, type, title; related peers may include file_id). "
        "Never invent file or object ids; only use ids returned by tools or listed in scope. "
        "Archived files are searchable/readable but never writable. "
        "Write tools: prefer move_text to insert one slice; patch_file for "
        "multi-spot edits (full new agent text); rewrite_file only for a true rewrite. "
        "Preserve every existing embed object_id; never omit fenced object blocks. "
        "When the user asks to add or change content, you must call a write tool — "
        "a text summary alone does not change the file. "
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


def sync_all_workspace_prompts(*, overwrite: bool = True) -> list[int]:
    """Overwrite (or seed) system_prompt for every workspace. Returns workspace ids."""
    ids = [row.id for row in Workspace.query.order_by(Workspace.id).all()]
    for workspace_id in ids:
        sync_prompt_from_file(workspace_id, overwrite=overwrite)
    if ids:
        db.session.commit()
    return ids


def _on_render() -> bool:
    # Render sets several of these; any one is enough.
    return any(
        (os.environ.get(key) or "").strip()
        for key in ("RENDER", "RENDER_SERVICE_ID", "RENDER_EXTERNAL_URL")
    )


def should_sync_prompt_on_boot() -> bool:
    """On Render, sync by default (internal DATABASE_URL). Locally opt-in via env."""
    flag = (os.environ.get("SYNC_AGENT_PROMPT_ON_DEPLOY") or "").strip().lower()
    if flag in {"0", "false", "no", "off"}:
        return False
    if flag in {"1", "true", "yes", "on"}:
        return True
    return _on_render()


def _boot_log(message: str) -> None:
    # print() so Render deploy logs show it even when app loggers are quiet.
    print(f"[agent-prompt] {message}", flush=True)
    logger.info(message)


def maybe_sync_prompts_on_boot() -> None:
    """Push git prompt into DB via the service's DATABASE_URL (internal on Render)."""
    if not should_sync_prompt_on_boot():
        _boot_log(
            "sync skipped "
            f"(RENDER={os.environ.get('RENDER')!r} "
            f"SYNC_AGENT_PROMPT_ON_DEPLOY={os.environ.get('SYNC_AGENT_PROMPT_ON_DEPLOY')!r})"
        )
        return
    path = resolve_prompt_file()
    if not path.is_file():
        _boot_log(f"sync skipped — file missing: {path}")
        return
    try:
        ids = sync_all_workspace_prompts(overwrite=True)
        _boot_log(f"synced from {path} for workspace(s): {ids}")
    except Exception as error:
        # Never block boot if DB is briefly unavailable.
        _boot_log(f"sync failed: {error}")
        logger.exception("agent prompt sync on boot failed")

