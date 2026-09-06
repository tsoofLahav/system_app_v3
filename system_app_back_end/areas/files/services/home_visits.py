"""Files visiting Home — the same row as on the source topic, membership only.

Stored on `workspaces.home_visit_file_ids`. Automations add a file; ⌘K / dismiss
on the client PUT the same list. The mixed Home canvas order (visits among
Home's own files) is `workspaces.home_canvas_file_ids` so phone and computer
share it. `topics.file_layout` stays desktop-only.
"""

from __future__ import annotations

from sqlalchemy.orm.attributes import flag_modified

from models import File, Topic, Workspace, db


def is_home_topic(topic: Topic | None) -> bool:
    if topic is None:
        return False
    return str(topic.name or "").strip().lower() == "home"


def _id_list(raw) -> list[int]:
    if not isinstance(raw, list):
        return []
    out = []
    seen = set()
    for item in raw:
        try:
            fid = int(item)
        except (TypeError, ValueError):
            continue
        if fid in seen:
            continue
        seen.add(fid)
        out.append(fid)
    return out


def visit_ids_of(workspace: Workspace) -> list[int]:
    return _id_list(workspace.home_visit_file_ids)


def canvas_ids_of(workspace: Workspace) -> list[int]:
    return _id_list(getattr(workspace, "home_canvas_file_ids", None))


def set_visit_ids(workspace: Workspace, ids: list[int]) -> list[int]:
    unique = _id_list(ids)
    workspace.home_visit_file_ids = unique
    flag_modified(workspace, "home_visit_file_ids")
    return unique


def set_canvas_ids(workspace: Workspace, ids: list[int]) -> list[int]:
    unique = _id_list(ids)
    workspace.home_canvas_file_ids = unique
    flag_modified(workspace, "home_canvas_file_ids")
    return unique


def live_visit_ids(workspace: Workspace) -> list[int]:
    """Drop archived / missing / Home-owned ids and persist the prune."""
    kept = []
    for file_id in visit_ids_of(workspace):
        file = db.session.get(File, file_id)
        if file is None or file.archived_at is not None:
            continue
        topic = db.session.get(Topic, file.topic_id)
        if topic is None or topic.archived_at is not None:
            continue
        if is_home_topic(topic):
            continue
        kept.append(file.id)
    if kept != visit_ids_of(workspace):
        set_visit_ids(workspace, kept)
    return kept


def add_home_visit(workspace: Workspace, file: File) -> bool:
    """Front of the list. Returns True when the file was not already visiting."""
    ids = live_visit_ids(workspace)
    if file.id in ids:
        return False
    set_visit_ids(workspace, [file.id, *ids])
    canvas = [fid for fid in canvas_ids_of(workspace) if fid != file.id]
    set_canvas_ids(workspace, [file.id, *canvas])
    return True
