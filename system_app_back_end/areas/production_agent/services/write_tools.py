"""Agent write tools: patch_file, rewrite_file.

Apply vs review is decided by the run's action config plus per-tool defaults —
the model does not choose the dialog.

- ``patch_file`` — partial edits via exact old→new replacements (change/delete/add)
- ``rewrite_file`` — replace the whole file's agent text
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
from areas.files.services.document_promote import promote_legacy_embeds
from areas.files.services.file_versions import save_file_version
from areas.objects.services.delete_cascade import purge_unreferenced_embeds_for_file
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


def _object_updates_json(updates: dict[int, dict[str, Any]]) -> dict[str, Any]:
    return {str(k): v for k, v in updates.items()}


def _object_updates_from_json(raw: dict[str, Any] | None) -> dict[int, dict[str, Any]]:
    if not raw:
        return {}
    out: dict[int, dict[str, Any]] = {}
    for key, value in raw.items():
        if not isinstance(value, dict):
            continue
        out[int(key)] = value
    return out


def commit_agent_file_apply(
    file: File,
    *,
    new_document_json: str,
    object_updates: dict[int, dict[str, Any]],
    source: str = "agent",
) -> list[str]:
    """Persist document + object rows atomically. Returns error strings."""
    if file.archived_at is not None:
        return ["archived files are read-only"]
    promote_legacy_embeds(file)
    save_file_version(file, source=source)
    file.document_json = new_document_json
    update_errors = apply_object_updates(file.id, object_updates)
    if update_errors:
        return update_errors
    purge_unreferenced_embeds_for_file(file)
    return []


def apply_replacements(
    current: str,
    replacements: list[dict[str, Any]],
) -> tuple[str | None, str | None]:
    """Apply exact unique old→new replacements. Return (new_text, error).

    Unmatched or ambiguous ``old_text`` fails — callers should re-open the file.
    Text outside the matched spans (including blank lines) is untouched.
    """
    if not replacements:
        return None, "replacements is empty"

    text = current
    for index, raw in enumerate(replacements, start=1):
        if not isinstance(raw, dict):
            return None, f"replacement {index}: must be an object"
        old = raw.get("old_text")
        if old is None:
            return None, f"replacement {index}: old_text is required"
        old = str(old)
        if old == "":
            return None, f"replacement {index}: old_text is empty"
        new = "" if raw.get("new_text") is None else str(raw.get("new_text"))
        count = text.count(old)
        if count == 0:
            return None, (
                f"replacement {index}: old_text not found — open_file and copy "
                "the exact span to replace"
            )
        if count > 1:
            return None, (
                f"replacement {index}: old_text matched {count} times — include "
                "more surrounding context so it is unique"
            )
        text = text.replace(old, new, 1)
    return text, None


def apply_document_text(
    file_id: int,
    document_text: str,
    *,
    scope: dict,
    write_mode: WriteMode,
    tool_name: str,
) -> dict[str, Any]:
    """Shared path: agent text → document_json (+ object updates)."""
    file = db.session.get(File, file_id)
    if file is None:
        return {"error": "file not found"}
    if not _file_in_scope(file, scope):
        return {"error": "file out of scope"}
    if file.archived_at is not None:
        return {"error": "archived files are read-only"}

    promote_legacy_embeds(file)
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
        "object_updates": _object_updates_json(object_updates),
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

    apply_errors = commit_agent_file_apply(
        file,
        new_document_json=new_document_json or "",
        object_updates=object_updates,
        source="agent",
    )
    if apply_errors:
        return {"error": "; ".join(apply_errors), "tool": tool_name}
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


def patch_file(
    file_id: int,
    replacements: list[dict[str, Any]],
    *,
    scope: dict,
    write_mode: WriteMode,
) -> dict[str, Any]:
    """Update a file in place via exact unique string replacements."""
    file = db.session.get(File, file_id)
    if file is None:
        return {"error": "file not found"}
    if not _file_in_scope(file, scope):
        return {"error": "file out of scope"}
    if file.archived_at is not None:
        return {"error": "archived files are read-only"}

    current = _current_agent_text(file)
    new_text, error = apply_replacements(current, replacements)
    if error:
        return {"error": error, "tool": "patch_file"}
    result = apply_document_text(
        file_id,
        new_text or "",
        scope=scope,
        write_mode=write_mode,
        tool_name="patch_file",
    )
    if "error" not in result:
        result["replacements"] = len(replacements)
    return result
