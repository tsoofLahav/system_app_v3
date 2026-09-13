"""File steps: make one, archive some."""

from __future__ import annotations

from datetime import datetime, timedelta

from models import File, Topic, TopicType, db
from areas.automations.services.name_match import pick_closest_named
from areas.automations.services.scope import live_topic_ids, target_topic_id
from areas.automations.services.steps import expand_name_tokens
from areas.files.services import file_ops
from areas.files.services.clone_topic_skeleton import clone_slot_into_topic


def _topics_in_scope(resolved: dict) -> list[int]:
    workspace_id = int(resolved["workspace_id"])
    topic_ids = resolved.get("topic_ids")
    if topic_ids is not None:
        return live_topic_ids(workspace_id, topic_ids)
    return live_topic_ids(workspace_id)


def files_in_scope(resolved: dict, *, older_than: datetime | None = None):
    query = File.query.filter(
        File.topic_id.in_(_topics_in_scope(resolved)),
        File.archived_at.is_(None),
    )
    if "file_ids" in resolved:
        query = query.filter(File.id.in_([int(i) for i in resolved["file_ids"]]))
    if older_than is not None:
        query = query.filter(File.created_at < older_than)
    return query.order_by(File.id).all()


def _template_source_for(topic: Topic) -> Topic | None:
    if topic.topic_type_id is None:
        return None
    type_row = db.session.get(TopicType, topic.topic_type_id)
    if type_row is None or not type_row.template_topic_id:
        return None
    return db.session.get(Topic, type_row.template_topic_id)


def create_file(*, workspace_id: int, resolved_scope: dict, params: dict, now: datetime):
    slot = str(params.get("template_slot") or "").strip()
    if slot:
        created: list[File] = []
        for topic_id in _topics_in_scope(resolved_scope):
            topic = db.session.get(Topic, int(topic_id))
            if topic is None or int(topic.workspace_id) != int(workspace_id):
                continue
            source = _template_source_for(topic)
            if source is None:
                continue
            file = clone_slot_into_topic(
                topic, source=source, template_slot=slot
            )
            if file is None:
                continue
            name = str(params.get("name") or "").strip()
            if name:
                file.name = expand_name_tokens(name, now=now)
            created.append(file)
        db.session.flush()
        return {
            "ok": True,
            "file_ids": [f.id for f in created],
            "summary": f"created {len(created)} file(s)",
        }

    topic_id = params.get("topic_id") or target_topic_id(resolved_scope)
    if topic_id is None:
        return {"error": "no topic to create in: scope covers more than one"}

    topic = db.session.get(Topic, int(topic_id))
    if topic is None or int(topic.workspace_id) != int(workspace_id):
        return {"error": "topic not found in this workspace"}

    name = expand_name_tokens(params.get("name") or "", now=now)
    try:
        file = file_ops.create_file(topic_id=topic.id, name=name)
    except ValueError as error:
        return {"error": str(error)}
    return {"ok": True, "file_id": file.id, "summary": f"created “{name}”"}


def _probe_name(params: dict, files: list) -> str | None:
    name = str(params.get("file_name") or "").strip()
    if name:
        return name
    file_id = params.get("file_id")
    if file_id is None:
        chosen = params.get("file_ids")
        if isinstance(chosen, list) and chosen:
            file_id = chosen[0]
    if file_id is None:
        return None
    for file in files:
        if int(file.id) == int(file_id):
            return str(file.name or "").strip() or None
    return None


def _pick_named_per_topic(files: list, params: dict, resolved: dict):
    probe = _probe_name(params, files)
    slot = str(params.get("template_slot") or "").strip()
    if not probe and slot:
        # Legacy configurations saved slot IDs. Resolve the reference name once;
        # matching targets never depends on their inherited slot metadata.
        for topic_id in _topics_in_scope(resolved):
            topic = db.session.get(Topic, topic_id)
            source = _template_source_for(topic) if topic else None
            candidates = File.query.filter_by(topic_id=source.id).all() if source else []
            match = next((f for f in candidates if (f.meta or {}).get("template_slot") == slot), None)
            if match is not None:
                probe = match.name
                break
        if not probe:
            match = next((f for f in files if (f.meta or {}).get("template_slot") == slot), None)
            probe = match.name if match else None
    if not probe:
        return [], [], {"error": "selected file name could not be resolved"}
    picked, missing = [], []
    for topic_id in _topics_in_scope(resolved):
        match = pick_closest_named(probe, [f for f in files if f.topic_id == topic_id])
        if match is None:
            topic = db.session.get(Topic, topic_id)
            missing.append({"topic_id": topic_id, "topic": topic.name if topic else str(topic_id), "file_name": probe})
        else:
            picked.append(match)
    return picked, missing, None


def _missing_summary(missing):
    return ("; no matching file in: " + ", ".join(m["topic"] for m in missing)) if missing else ""


def archive_files(*, workspace_id: int, resolved_scope: dict, params: dict, now: datetime):
    older_than = None
    if params.get("older_than_days") is not None:
        older_than = now - timedelta(days=int(params["older_than_days"]))

    files = files_in_scope(resolved_scope, older_than=older_than)
    missing = []
    if any(params.get(k) for k in ("template_slot", "file_name", "file_id", "file_ids")):
        files, missing, error = _pick_named_per_topic(files, params, resolved_scope)
        if error:
            return error
    for file in files:
        file_ops.archive_file(file, when=now)
    db.session.flush()
    return {
        "ok": True,
        "file_ids": [f.id for f in files],
        "summary": f"archived {len(files)} file(s)" + _missing_summary(missing),
        "missing_topics": missing,
    }


def fill_file(*, workspace_id: int, resolved_scope: dict, params: dict, now: datetime):
    """Append a saved snippet onto matching live files."""
    from areas.files.services.file_snapshot import apply_snippet_to_file
    from areas.files.services.file_versions import save_file_version

    snapshot = {
        "document_json": params.get("document_json") or "",
        "objects": params.get("objects") or [],
    }
    files = files_in_scope(resolved_scope)
    files, missing, error = _pick_named_per_topic(files, params, resolved_scope)
    if error:
        return error
    for file in files:
        save_file_version(file, source="automation")
        apply_snippet_to_file(file, snapshot, append=True)
    db.session.flush()
    return {
        "ok": True,
        "file_ids": [f.id for f in files],
        "summary": f"added content to {len(files)} file(s)" + _missing_summary(missing),
        "missing_topics": missing,
    }


def bring_file(*, workspace_id: int, resolved_scope: dict, params: dict, now: datetime):
    """Project one live file from scope onto Home. Same file, still owned by its topic."""
    from models import Workspace
    from areas.files.services.home_visits import add_home_visit, is_home_topic

    files = files_in_scope(resolved_scope)
    if not str(params.get("file_name") or "").strip() and params.get("file_id") is None:
        return {"error": "no file to project"}
    files, missing, error = _pick_named_per_topic(files, params, resolved_scope)
    if error:
        return error
    workspace = db.session.get(Workspace, int(workspace_id))
    if workspace is None:
        return {"error": "workspace not found"}
    added = []
    for file in files:
        topic = db.session.get(Topic, file.topic_id)
        if not is_home_topic(topic) and add_home_visit(workspace, file):
            added.append(file.id)
    db.session.flush()
    return {"ok": True, "file_ids": added,
            "summary": f"projected {len(added)} file(s) onto Home" + _missing_summary(missing),
            "missing_topics": missing}
