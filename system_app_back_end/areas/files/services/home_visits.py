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
    if topic.id is None:
        return str(topic.name or "").strip().lower() == "home"
    home = home_topic_for_workspace(topic.workspace_id)
    return home is not None and home.id == topic.id


def home_topic_for_workspace(workspace_id: int) -> Topic | None:
    """Find Home by its bootstrapped Daily file, even after a rename."""
    rows = (
        db.session.query(File, Topic)
        .join(Topic, File.topic_id == Topic.id)
        .filter(Topic.workspace_id == workspace_id)
        .order_by(Topic.id, File.id)
        .all()
    )
    for file, topic in rows:
        if (file.meta or {}).get("automation_anchor") == "daily" and not topic.is_system:
            return topic
    return (
        Topic.query.filter_by(workspace_id=workspace_id)
        .filter(db.func.lower(Topic.name) == "home")
        .first()
    )


def restore_home_topic(workspace_id: int) -> Topic | None:
    """Repair the name and appearance expected by existing app clients."""
    topic = home_topic_for_workspace(workspace_id)
    if topic is not None:
        topic.name = "Home"
        topic.color = None
        topic.topic_type_id = None
    return topic


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
