"""Persist and finish agent pending reviews (per-hunk lookalike diff)."""

from __future__ import annotations

import copy
import re
from datetime import datetime
from difflib import SequenceMatcher
from typing import Any

from models import (
    AgentPendingReview,
    File,
    InformationPiece,
    ObjectEmbed,
    Task,
    TaskList,
    Topic,
    db,
)
from areas.files.services.document_agent_text import apply_agent_text_to_file
from areas.files.services.document_marker_text import embed_ids_in_text
from areas.files.services.document_v3 import sync_object_anchors
from areas.production_agent.services.write_tools import (
    _known_object_ids,
    _object_updates_from_json,
    commit_agent_file_apply,
)

_POINTER_ID_RE = re.compile(
    r'(\[(?:TABLE|GRAPH|INFO|TASK_LIST|IMAGE|EMBED)\b[^\]]*?\bid=")(\d+)(")'
)

# Opcode tuple: (tag, i1, i2, j1, j2) — same shape as SequenceMatcher.
_Opcode = tuple[str, int, int, int, int]


def _coalesce_opcodes(opcodes: list[_Opcode]) -> list[_Opcode]:
    """Merge adjacent delete+insert (either order) into a single replace.

    Prevents a conceptual line edit from applying as “keep old + insert new”
    when difflib emits separate delete/insert instead of replace.
    """
    if not opcodes:
        return []
    out: list[_Opcode] = []
    i = 0
    while i < len(opcodes):
        tag, i1, i2, j1, j2 = opcodes[i]
        if i + 1 < len(opcodes):
            ntag, ni1, ni2, nj1, nj2 = opcodes[i + 1]
            if tag == "delete" and ntag == "insert" and i2 == ni1 and j2 == nj1:
                out.append(("replace", i1, i2, j1, nj2))
                i += 2
                continue
            if tag == "insert" and ntag == "delete" and i2 == ni1 and j2 == nj1:
                out.append(("replace", i1, ni2, j1, j2))
                i += 2
                continue
        out.append((tag, i1, i2, j1, j2))
        i += 1
    return out


def normalized_opcodes(old_text: str, new_text: str) -> list[_Opcode]:
    old_lines = (old_text or "").splitlines()
    new_lines = (new_text or "").splitlines()
    raw = list(
        SequenceMatcher(a=old_lines, b=new_lines, autojunk=False).get_opcodes()
    )
    return _coalesce_opcodes(raw)


def build_hunks(old_text: str, new_text: str) -> list[dict[str, Any]]:
    old_lines = (old_text or "").splitlines()
    new_lines = (new_text or "").splitlines()
    hunks: list[dict[str, Any]] = []
    for tag, i1, i2, j1, j2 in normalized_opcodes(old_text, new_text):
        if tag == "equal":
            continue
        op = {"insert": "add", "delete": "remove", "replace": "change"}.get(tag, tag)
        hunks.append(
            {
                "id": f"{op}-{i1}-{j1}",
                "op": op,
                "old_start": i1 + 1,
                "old_end": i2,
                "new_start": j1 + 1,
                "new_end": j2,
                "old_lines": old_lines[i1:i2],
                "new_lines": new_lines[j1:j2],
            }
        )
    return hunks


def merge_agent_text(
    old_text: str,
    new_text: str,
    decisions: list[dict[str, Any]],
) -> tuple[str | None, str | None]:
    """Return (chosen_text, error). Every hunk must appear in decisions.

    Walks the same normalized opcodes as ``build_hunks`` so Accept on a change
    replaces (never keeps old + inserts new).
    """
    old_lines = (old_text or "").splitlines()
    new_lines = (new_text or "").splitlines()
    opcodes = normalized_opcodes(old_text, new_text)
    hunks = build_hunks(old_text, new_text)
    by_id = {str(d.get("hunk_id")): d.get("choice") for d in decisions}
    if len(hunks) != len(by_id) or any(h["id"] not in by_id for h in hunks):
        return None, "every hunk must have accept or reject"
    for h in hunks:
        choice = by_id[h["id"]]
        if choice not in {"accept", "reject"}:
            return None, f"invalid choice for hunk {h['id']}"

    out: list[str] = []
    hunk_iter = iter(hunks)
    for tag, i1, i2, j1, j2 in opcodes:
        if tag == "equal":
            out.extend(old_lines[i1:i2])
            continue
        hunk = next(hunk_iter)
        accept = by_id[hunk["id"]] == "accept"
        if tag == "insert":
            if accept:
                out.extend(new_lines[j1:j2])
        elif tag == "delete":
            if not accept:
                out.extend(old_lines[i1:i2])
        elif tag == "replace":
            # Accept → only new; reject → only old. Never concatenate.
            out.extend(new_lines[j1:j2] if accept else old_lines[i1:i2])
    text = "\n".join(out)
    if (old_text or "").endswith("\n") or (new_text or "").endswith("\n"):
        if text and not text.endswith("\n"):
            text += "\n"
    return text, None


def upsert_pending_from_proposals(
    *,
    workspace_id: int,
    run_key: str,
    proposed_changes: list[dict],
) -> list[int]:
    """Replace open pending per file. Caller commits."""
    saved_ids: list[int] = []
    for change in proposed_changes:
        if not isinstance(change, dict):
            continue
        if change.get("tool") == "create_object":
            continue
        review = change.get("review")
        if not isinstance(review, dict):
            continue
        file_id = change.get("file_id")
        if file_id is None:
            continue
        file = db.session.get(File, int(file_id))
        if file is None:
            continue
        topic = db.session.get(Topic, file.topic_id)
        if topic is None or int(topic.workspace_id) != int(workspace_id):
            continue

        old_agent = str(review.get("old_document_text") or "")
        new_agent = str(review.get("new_document_text") or change.get("document_text") or "")
        old_doc = str(change.get("old_document_json") or "")
        new_doc = str(change.get("new_document_json") or "")
        if not old_agent and not new_agent:
            continue

        existing = AgentPendingReview.query.filter_by(file_id=file.id).first()
        if existing is None:
            existing = AgentPendingReview(file_id=file.id)
            db.session.add(existing)
        existing.workspace_id = int(workspace_id)
        existing.topic_id = file.topic_id
        existing.run_key = run_key or ""
        existing.old_agent_text = old_agent
        existing.new_agent_text = new_agent
        existing.old_document_json = old_doc
        existing.new_document_json = new_doc
        existing.object_updates = change.get("object_updates") or {}
        existing.tool = str(change.get("tool") or "patch_file")
        existing.created_at = datetime.utcnow()
        db.session.flush()
        saved_ids.append(int(existing.id))
    return saved_ids


def get_pending_for_file(file_id: int) -> dict[str, Any] | None:
    row = AgentPendingReview.query.filter_by(file_id=int(file_id)).first()
    if row is None:
        return None
    data = row.to_dict()
    data["hunks"] = build_hunks(row.old_agent_text, row.new_agent_text)
    return data


def discard_pending(file_id: int) -> bool:
    row = AgentPendingReview.query.filter_by(file_id=int(file_id)).first()
    if row is None:
        return False
    db.session.delete(row)
    return True


def _rewrite_pointer_ids(text: str, id_map: dict[int, int]) -> str:
    def repl(match: re.Match[str]) -> str:
        old_id = int(match.group(2))
        new_id = id_map.get(old_id, old_id)
        return f"{match.group(1)}{new_id}{match.group(3)}"

    return _POINTER_ID_RE.sub(repl, text or "")


def _clone_embed_to_file(src: ObjectEmbed, dest_file_id: int) -> ObjectEmbed:
    task_list_id = None
    information_id = None
    if src.type == "task_list" and src.task_list_id:
        src_list = db.session.get(TaskList, src.task_list_id)
        title = src_list.title if src_list else ""
        new_list = TaskList(title=title or "")
        db.session.add(new_list)
        db.session.flush()
        task_list_id = new_list.id
        tasks = Task.query.filter_by(task_list_id=src.task_list_id).all()
        for t in tasks:
            db.session.add(
                Task(
                    task_list_id=new_list.id,
                    title=t.title,
                    status=t.status,
                    due_date=t.due_date,
                    list_order_index=t.list_order_index,
                    archived_at=t.archived_at,
                )
            )
    elif src.type == "info" and src.information_id:
        src_info = db.session.get(InformationPiece, src.information_id)
        info = InformationPiece(
            title=(src_info.title if src_info else "") or "",
            body=(src_info.body if src_info else "") or "",
            metadata_=copy.deepcopy(src_info.metadata_) if src_info else {},
        )
        db.session.add(info)
        db.session.flush()
        information_id = info.id

    clone = ObjectEmbed(
        file_id=dest_file_id,
        type=src.type,
        task_list_id=task_list_id,
        information_id=information_id,
        payload=copy.deepcopy(src.payload) if src.payload is not None else {},
        anchor={},
        sort_key=src.sort_key,
    )
    db.session.add(clone)
    db.session.flush()
    clone.anchor = {"kind": "embed", "object_id": clone.id}
    return clone


def archive_copy_of_document(
    *,
    live_file: File,
    old_document_json: str,
    archive_name: str,
) -> File:
    """Deep-copy embeds into a new archived file in the same topic."""
    archived = File(
        topic_id=live_file.topic_id,
        name=archive_name,
        document_json=old_document_json or "",
        order_index=live_file.order_index,
        meta=copy.deepcopy(live_file.meta) if live_file.meta else {},
        archived_at=datetime.utcnow(),
    )
    db.session.add(archived)
    db.session.flush()

    ids = embed_ids_in_text(old_document_json or "")
    id_map: dict[int, int] = {}
    for old_id in sorted(ids):
        src = db.session.get(ObjectEmbed, old_id)
        if src is None:
            continue
        clone = _clone_embed_to_file(src, archived.id)
        id_map[old_id] = clone.id

    rewritten = _rewrite_pointer_ids(old_document_json or "", id_map)
    archived.document_json = rewritten
    embeds = ObjectEmbed.query.filter_by(file_id=archived.id).all()
    sync_object_anchors(archived.document_json or "", embeds)
    db.session.flush()
    return archived


def finish_pending(
    file_id: int,
    *,
    decisions: list[dict[str, Any]],
    archive_name: str | None = None,
) -> dict[str, Any]:
    live = db.session.get(File, int(file_id))
    if live is None:
        return {"error": "file not found"}
    if live.archived_at is not None:
        return {"error": "archived files are read-only"}
    pending = AgentPendingReview.query.filter_by(file_id=live.id).first()
    if pending is None:
        return {"error": "no pending review"}

    chosen, err = merge_agent_text(
        pending.old_agent_text,
        pending.new_agent_text,
        decisions,
    )
    if err or chosen is None:
        return {"error": err or "merge failed"}

    name = archive_name or (
        f"{live.name} (before AI · {datetime.utcnow().strftime('%Y-%m-%d')})"
    )
    archive_copy_of_document(
        live_file=live,
        old_document_json=pending.old_document_json or live.document_json or "",
        archive_name=name,
    )

    known_ids = _known_object_ids(live.id)
    new_document_json, object_updates, errors = apply_agent_text_to_file(
        live.id,
        live.document_json or "",
        chosen,
        known_object_ids=known_ids,
    )
    if errors:
        return {"error": "; ".join(errors)}

    apply_errors = commit_agent_file_apply(
        live,
        new_document_json=new_document_json or "",
        object_updates=object_updates,
        source="agent",
    )
    if apply_errors:
        return {"error": "; ".join(apply_errors)}

    db.session.delete(pending)
    db.session.flush()
    return {
        "ok": True,
        "file_id": live.id,
        "archived_name": name,
        "chosen_agent_text": chosen,
    }
