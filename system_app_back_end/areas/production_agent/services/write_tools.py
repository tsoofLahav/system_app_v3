"""Agent write tools: patch_file, move_text, rewrite_file.

Apply vs review is decided by the run's action config plus per-tool defaults —
the model does not choose the dialog.
"""

from __future__ import annotations

import difflib
from typing import Any, Literal

from models import File, ObjectEmbed, db
from areas.files.services.document_agent_text import (
    apply_agent_text_to_file,
    apply_object_updates,
    document_to_agent_text,
    load_objects_by_id,
)
from areas.files.services.file_versions import save_file_version
from shared.run_config import DEFAULT_MANUAL_APPLY_MODE

WriteMode = Literal["review", "direct_apply", "notify_only"]


def compute_diff(
    old_document_json: str,
    new_document_json: str,
    *,
    file_id: int | None = None,
    objects_by_id: dict[int, dict[str, Any]] | None = None,
) -> dict:
    if objects_by_id is None and file_id is not None:
        objects_by_id = load_objects_by_id(file_id)
    objects_by_id = objects_by_id or {}
    old_plain = document_to_agent_text(old_document_json, objects_by_id=objects_by_id)
    new_plain = document_to_agent_text(new_document_json, objects_by_id=objects_by_id)
    old_lines = old_plain.splitlines(keepends=True)
    new_lines = new_plain.splitlines(keepends=True)
    hunks = list(
        difflib.unified_diff(
            old_lines,
            new_lines,
            fromfile="before",
            tofile="after",
        )
    )
    return {
        "diff_hunks": "".join(hunks),
        "old_document_text": old_plain,
        "new_document_text": new_plain,
    }

# Typical outcomes from the plan when the run allows direct apply.
TOOL_WRITE_DEFAULTS: dict[str, WriteMode] = {
    "patch_file": "review",
    "move_text": "direct_apply",
    "rewrite_file": "direct_apply",
}

WRITE_TOOL_NAMES = frozenset(TOOL_WRITE_DEFAULTS)


def resolve_write_mode(tool_name: str, run_apply_mode: str) -> WriteMode:
    """Run apply_mode wins. Unknown modes fall back to per-tool defaults."""
    run_mode = (run_apply_mode or DEFAULT_MANUAL_APPLY_MODE).strip()
    if run_mode == "notify_only":
        return "notify_only"
    if run_mode == "review":
        return "review"
    if run_mode == "direct_apply":
        return "direct_apply"
    return TOOL_WRITE_DEFAULTS.get(tool_name, "review")


def _file_in_scope(file: File, scope: dict) -> bool:
    file_ids = [int(x) for x in (scope.get("file_ids") or [])]
    topic_ids = [int(x) for x in (scope.get("topic_ids") or [])]
    if file_ids:
        return file.id in file_ids
    if topic_ids:
        return file.topic_id in topic_ids
    return False


def _known_object_ids(file_id: int) -> set[int]:
    embeds = ObjectEmbed.query.filter_by(file_id=file_id).all()
    return {int(e.id) for e in embeds}


def _current_agent_text(file: File) -> str:
    objects_by_id = load_objects_by_id(file.id)
    return document_to_agent_text(file.document_json or "", objects_by_id=objects_by_id)


def apply_document_text(
    file_id: int,
    document_text: str,
    *,
    scope: dict,
    write_mode: WriteMode,
    tool_name: str,
) -> dict[str, Any]:
    """Shared replace path used by patch_file and rewrite_file."""
    file = db.session.get(File, file_id)
    if file is None:
        return {"error": "file not found"}
    if not _file_in_scope(file, scope):
        return {"error": "file out of scope"}
    if file.archived_at is not None:
        return {"error": "archived files are read-only"}

    old_document = file.document_json or ""
    known_ids = _known_object_ids(file_id)
    new_document_json, object_updates, errors = apply_agent_text_to_file(
        file_id,
        old_document,
        document_text,
        known_object_ids=known_ids,
    )
    if errors:
        return {"error": "; ".join(errors), "tool": tool_name}

    base = {
        "tool": tool_name,
        "file_id": file_id,
        "old_document_json": old_document,
        "new_document_json": new_document_json,
        "document_text": document_text,
        "write_mode": write_mode,
    }

    if write_mode == "notify_only":
        return {**base, "applied": False}
    if write_mode == "review":
        return {
            **base,
            "applied": False,
            "review": compute_diff(
                old_document, new_document_json or "", file_id=file_id
            ),
        }

    save_file_version(file, source="agent")
    file.document_json = new_document_json
    update_errors = apply_object_updates(file_id, object_updates)
    if update_errors:
        return {"error": "; ".join(update_errors), "tool": tool_name}
    db.session.flush()
    return {**base, "applied": True}


def insert_agent_text(
    current: str,
    content: str,
    *,
    anchor_type: str,
    line: int = 0,
    text: str = "",
) -> tuple[str | None, str | None]:
    """Return (new_agent_text, error)."""
    slice_text = (content or "").strip("\n")
    if not slice_text:
        return None, "content is empty"

    lines = current.splitlines()
    anchor = (anchor_type or "end").strip().lower()

    if anchor == "end":
        if current.strip():
            new_text = current.rstrip() + "\n\n" + slice_text + "\n"
        else:
            new_text = slice_text + "\n"
        return new_text, None

    if anchor == "start":
        if current.strip():
            new_text = slice_text + "\n\n" + current.lstrip()
        else:
            new_text = slice_text + "\n"
        return new_text, None

    if anchor in {"after_line", "before_line"}:
        # 1-based line numbers in agent text.
        if line < 1:
            return None, "line must be >= 1 for after_line/before_line"
        idx = line - 1
        if idx > len(lines):
            return None, f"line {line} past end of file ({len(lines)} lines)"
        insert_at = idx + 1 if anchor == "after_line" else idx
        insert_at = max(0, min(insert_at, len(lines)))
        new_lines = lines[:insert_at] + slice_text.splitlines() + lines[insert_at:]
        return "\n".join(new_lines) + ("\n" if current.endswith("\n") else ""), None

    if anchor == "after_text":
        needle = (text or "").strip()
        if not needle:
            return None, "text required for after_text anchor"
        for i, row in enumerate(lines):
            if needle in row:
                new_lines = lines[: i + 1] + slice_text.splitlines() + lines[i + 1 :]
                return (
                    "\n".join(new_lines) + ("\n" if current.endswith("\n") else ""),
                    None,
                )
        return None, f"anchor text not found: {needle!r}"

    return None, f"unknown anchor_type: {anchor_type}"


def move_text(
    file_id: int,
    content: str,
    *,
    scope: dict,
    write_mode: WriteMode,
    anchor_type: str = "end",
    line: int = 0,
    text: str = "",
) -> dict[str, Any]:
    file = db.session.get(File, file_id)
    if file is None:
        return {"error": "file not found"}
    if not _file_in_scope(file, scope):
        return {"error": "file out of scope"}
    if file.archived_at is not None:
        return {"error": "archived files are read-only"}

    current = _current_agent_text(file)
    new_text, error = insert_agent_text(
        current,
        content,
        anchor_type=anchor_type,
        line=line,
        text=text,
    )
    if error:
        return {"error": error, "tool": "move_text"}
    result = apply_document_text(
        file_id,
        new_text or "",
        scope=scope,
        write_mode=write_mode,
        tool_name="move_text",
    )
    if "error" not in result:
        result["anchor"] = {
            "type": anchor_type,
            "line": line,
            "text": text,
        }
    return result
