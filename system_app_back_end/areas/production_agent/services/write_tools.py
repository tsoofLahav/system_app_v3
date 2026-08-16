"""Agent write tools: patch_file, rewrite_file.

Apply vs review is decided by the run's action config plus per-tool defaults —
the model does not choose the dialog.

- ``patch_file`` — partial edits via add / remove / replace line ops
- ``rewrite_file`` — replace the whole file's agent text
"""

from __future__ import annotations

import difflib
from typing import Any, Literal

from models import File, ObjectEmbed, Topic, db
from areas.files.services.document_agent_text import (
    apply_agent_text_to_file,
    apply_object_updates,
    document_to_agent_text,
    load_objects_by_id,
)
from areas.files.services.document_promote import promote_legacy_embeds
from areas.files.services.file_versions import save_file_version
from areas.objects.services.delete_cascade import purge_unreferenced_embeds_for_file
from areas.production_agent.services.browse_tools import file_allowed
from shared.run_config import DEFAULT_MANUAL_APPLY_MODE

WriteMode = Literal["review", "direct_apply", "notify_only"]

_UNDO_PREVIEW_MAX = 100


def build_undo_card(
    *,
    file: File,
    old_document_json: str,
    new_agent_text: str,
) -> dict[str, Any]:
    """Compact undo payload for a just-applied direct write."""
    # Lazy import avoids circular import with pending_reviews.
    from areas.production_agent.services.pending_reviews import build_hunks

    topic = db.session.get(Topic, file.topic_id) if file.topic_id else None
    objects_by_id = load_objects_by_id(file.id)
    old_plain = document_to_agent_text(
        old_document_json or "",
        objects_by_id=objects_by_id,
    )
    hunks = build_hunks(old_plain, new_agent_text or "")
    changes: list[dict[str, str]] = []
    for h in hunks:
        op = str(h.get("op") or "change")
        if op == "add":
            lines = h.get("new_lines") or []
        elif op == "remove":
            lines = h.get("old_lines") or []
        else:
            lines = h.get("new_lines") or h.get("old_lines") or []
        preview = str(lines[0]) if lines else ""
        if len(preview) > _UNDO_PREVIEW_MAX:
            preview = preview[: _UNDO_PREVIEW_MAX - 3] + "..."
        changes.append({"op": op, "text": preview})
    return {
        "file_id": file.id,
        "file_name": file.name or "",
        "topic_id": file.topic_id,
        "topic_name": (topic.name if topic else "") or "",
        "old_document_json": old_document_json or "",
        "changes": changes,
    }


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
    "create_object": "direct_apply",
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
    return file_allowed(file, scope)


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


def apply_line_edits(
    current: str,
    edits: list[dict[str, Any]],
) -> tuple[str | None, str | None]:
    """Apply add / remove / replace line ops. Return (new_text, error).

    Line numbers are 1-based from ``document_lines``.
    - ``add``: insert ``text`` **after** ``line`` (``line=0`` = start of file)
    - ``remove``: delete ``line`` (``end_line`` unused; pass 0)
    - ``replace``: replace inclusive ``line``..``end_line`` with ``text``

    Ops are applied from bottom to top so earlier line numbers stay valid.
    """
    if not edits:
        return None, "edits is empty"

    lines = current.splitlines()
    ends_with_newline = current.endswith("\n")
    line_count = len(lines)

    # (sort_line, orig_index, kind, start, end, new_lines)
    normalized: list[tuple[int, int, str, int, int, list[str]]] = []
    for index, raw in enumerate(edits, start=1):
        if not isinstance(raw, dict):
            return None, f"edit {index}: must be an object"
        op = str(raw.get("op") or "").strip().lower()
        if op not in {"add", "remove", "replace"}:
            return None, f"edit {index}: op must be add, remove, or replace"
        try:
            line = int(raw["line"])
        except (KeyError, TypeError, ValueError):
            return None, f"edit {index}: line is required"
        try:
            end_line = int(raw.get("end_line") or 0)
        except (TypeError, ValueError):
            return None, f"edit {index}: end_line must be an integer"
        text = "" if raw.get("text") is None else str(raw.get("text"))
        new_lines = text.splitlines()

        if op == "add":
            if line < 0 or line > line_count:
                return None, (
                    f"edit {index}: add after line {line} past end of file "
                    f"({line_count} lines); use 0 to insert at start"
                )
            if not new_lines:
                return None, f"edit {index}: add requires non-empty text"
            normalized.append((line, index, "add", line, line, new_lines))
        elif op == "remove":
            if line < 1 or line > line_count:
                return None, (
                    f"edit {index}: remove line {line} past end of file "
                    f"({line_count} lines)"
                )
            normalized.append((line, index, "remove", line, line, []))
        else:  # replace
            end = end_line if end_line else line
            if line < 1 or end < 1:
                return None, f"edit {index}: replace line numbers must be >= 1"
            if end < line:
                return None, (
                    f"edit {index}: end_line ({end}) must be >= line ({line})"
                )
            if line > line_count or end > line_count:
                return None, (
                    f"edit {index}: replace range {line}-{end} past end of file "
                    f"({line_count} lines)"
                )
            normalized.append((line, index, "replace", line, end, new_lines))

    normalized.sort(key=lambda item: (item[0], item[1]), reverse=True)
    for _sort, _idx, kind, start, end, new_lines in normalized:
        if kind == "add":
            # after line start → insert at 0-based index `start`
            at = start
            lines[at:at] = new_lines
        elif kind == "remove":
            del lines[start - 1]
        else:
            lines[start - 1 : end] = new_lines

    new_text = "\n".join(lines)
    if ends_with_newline and new_text and not new_text.endswith("\n"):
        new_text += "\n"
    return new_text, None


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

    # Build undo from pre-commit object state + agent text just applied.
    undo = build_undo_card(
        file=file,
        old_document_json=old_document,
        new_agent_text=document_text,
    )
    apply_errors = commit_agent_file_apply(
        file,
        new_document_json=new_document_json or "",
        object_updates=object_updates,
        source="agent",
    )
    if apply_errors:
        return {"error": "; ".join(apply_errors), "tool": tool_name}
    db.session.flush()
    return {**base, "applied": True, "undo": undo}


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
    edits: list[dict[str, Any]],
    *,
    scope: dict,
    write_mode: WriteMode,
) -> dict[str, Any]:
    """Update a file in place via inclusive 1-based line-range edits."""
    file = db.session.get(File, file_id)
    if file is None:
        return {"error": "file not found"}
    if not _file_in_scope(file, scope):
        return {"error": "file out of scope"}
    if file.archived_at is not None:
        return {"error": "archived files are read-only"}

    current = _current_agent_text(file)
    new_text, error = apply_line_edits(current, edits)
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
        result["edits"] = len(edits)
    return result
