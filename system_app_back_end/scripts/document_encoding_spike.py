#!/usr/bin/env python3
"""Phase 0 spike: compare marker text vs JSON runs for diff readability."""

from __future__ import annotations

import difflib
import json


def marker_body() -> str:
    return """# Weekly goals

Ship the rewrite.

{{task:42}}
{{task:43}}

Follow up with design review.
"""


def runs_body() -> str:
    runs = {
        "runs": [
            {"type": "text", "text": "# Weekly goals\n\nShip the rewrite.\n\n"},
            {"type": "task", "object_id": 42},
            {"type": "task", "object_id": 43},
            {"type": "text", "text": "\n\nFollow up with design review.\n"},
        ]
    }
    return json.dumps(runs, indent=2)


def unified_diff(old: str, new: str, label: str) -> str:
    lines = difflib.unified_diff(
        old.splitlines(keepends=True),
        new.splitlines(keepends=True),
        fromfile=f"{label}/before",
        tofile=f"{label}/after",
    )
    return "".join(lines)


def main() -> None:
    old_marker = marker_body()
    new_marker = old_marker.replace("Ship the rewrite.", "Ship the v2 rewrite.")
    new_marker = new_marker.replace("{{task:43}}", "{{task:99}}")

    old_runs = runs_body()
    new_runs = old_runs.replace("Ship the rewrite.", "Ship the v2 rewrite.").replace(
        '"object_id": 43', '"object_id": 99'
    )

    print("=== Marker diff (lines:", len(unified_diff(old_marker, new_marker, "marker").splitlines()), ") ===")
    print(unified_diff(old_marker, new_marker, "marker"))
    print()
    print("=== JSON runs diff (lines:", len(unified_diff(old_runs, new_runs, "runs").splitlines()), ") ===")
    print(unified_diff(old_runs, new_runs, "runs"))


if __name__ == "__main__":
    main()
