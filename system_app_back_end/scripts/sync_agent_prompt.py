#!/usr/bin/env python3
"""Sync content/production_agent/system_prompt.md into agent_configs.system_prompt."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from app import app  # noqa: E402
from models import Workspace, db  # noqa: E402
from areas.production_agent.services.prompt import sync_prompt_from_file  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--workspace-id",
        type=int,
        help="Workspace to update (default: first workspace)",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Replace existing system_prompt even when non-empty",
    )
    args = parser.parse_args()

    with app.app_context():
        if args.workspace_id is not None:
            workspace_ids = [args.workspace_id]
        else:
            workspace_ids = [row.id for row in Workspace.query.order_by(Workspace.id).all()]

        if not workspace_ids:
            print("No workspaces found.", file=sys.stderr)
            return 1

        for workspace_id in workspace_ids:
            sync_prompt_from_file(workspace_id, overwrite=args.overwrite)
        db.session.commit()
        print(f"Synced production agent prompt for workspace(s): {workspace_ids}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
