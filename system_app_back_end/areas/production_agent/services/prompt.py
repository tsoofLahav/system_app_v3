"""Production agent system prompt — loaded from agent_configs in the database."""

from __future__ import annotations

import logging
import os
import re
from pathlib import Path

from models import AgentConfig, Workspace, db

DEFAULT_CONFIG_NAME = "default"
DEFAULT_TOOL_ALLOWLIST = [
    "search",
    "open_file",
    "reference",
    "patch_file",
    "move_text",
    "rewrite_file",
    "search_tasks",
]
_HERE = Path(__file__).resolve()
# Monorepo root (…/system_app) when services live under system_app_back_end/areas/…
REPO_ROOT = _HERE.parents[4]
_CONTENT_DIR = REPO_ROOT / "content" / "production_agent"
PROMPT_FILE = _CONTENT_DIR / "system_prompt.md"
REFERENCE_FILE = _CONTENT_DIR / "reference.md"
# Fallback if Root Directory packaging ever omits the sibling content/ tree.
_BACKEND_CONTENT_DIR = _HERE.parents[3] / "content" / "production_agent"
_BACKEND_PROMPT_FILE = _BACKEND_CONTENT_DIR / "system_prompt.md"
_BACKEND_REFERENCE_FILE = _BACKEND_CONTENT_DIR / "reference.md"

REFERENCE_SECTIONS = frozenset({"agent_text", "tools", "all"})

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


def resolve_reference_file() -> Path:
    if REFERENCE_FILE.is_file():
        return REFERENCE_FILE
    if _BACKEND_REFERENCE_FILE.is_file():
        return _BACKEND_REFERENCE_FILE
    return REFERENCE_FILE


_H2_SECTION_RE = re.compile(r"^## ([a-z_]+)\s*$", re.MULTILINE)


def load_reference_section(section: str) -> str:
    """Return a slice of content/production_agent/reference.md for the agent."""
    key = (section or "all").strip().lower()
    if key not in REFERENCE_SECTIONS:
        return (
            f"Unknown section {section!r}. Use one of: "
            + ", ".join(sorted(REFERENCE_SECTIONS))
        )
    path = resolve_reference_file()
    if not path.is_file():
        return "Reference file missing on server."
    text = path.read_text(encoding="utf-8")
    if key == "all":
        return text
    match = re.search(rf"^## {re.escape(key)}\s*$", text, re.MULTILINE)
    if not match:
        return f"Section {key!r} not found in reference."
    next_h2 = _H2_SECTION_RE.search(text, match.end())
    end = next_h2.start() if next_h2 else len(text)
    return text[match.start() : end].strip() + "\n"


def operational_suffix() -> str:
    return (
        "\n\nOperational: first message = prompt + scope (+ hints); no file bodies. "
        "A summary alone does not save — call write tools. "
        "reference(section) for examples when needed."
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

