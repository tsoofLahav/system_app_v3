"""Workspace browse tools: list / find_file / find_object."""

from __future__ import annotations

from typing import Any

from models import (
    File,
    InformationPiece,
    ObjectEmbed,
    TaskList,
    Topic,
    TopicType,
    db,
)
from areas.files.services.document_agent_text import (
    document_to_agent_text,
    load_objects_by_id,
)
from areas.files.services.document_marker_text import (
    editor_text_body,
    wrap_editor_text,
)
from areas.objects.services.table_payload import chart_enabled

# Re-use private splitter — same contract as insert_embed_pointer.
from areas.files.services import document_marker_text as marker_text


def file_in_workspace(file: File, workspace_id: int) -> bool:
    topic = db.session.get(Topic, file.topic_id)
    return topic is not None and int(topic.workspace_id) == int(workspace_id)


def file_allowed(file: File, scope: dict) -> bool:
    """Workspace membership when ``workspace_id`` is set; else legacy allow-list."""
    workspace_id = scope.get("workspace_id")
    if workspace_id is not None:
        return file_in_workspace(file, int(workspace_id))
    file_ids = [int(x) for x in (scope.get("file_ids") or [])]
    topic_ids = [int(x) for x in (scope.get("topic_ids") or [])]
    if file_ids:
        return file.id in file_ids
    if topic_ids:
        return file.topic_id in topic_ids
    return False


def _workspace_topics(workspace_id: int, *, include_archived: bool = False):
    q = Topic.query.filter_by(workspace_id=workspace_id, is_template=False)
    if not include_archived:
        q = q.filter(Topic.archived_at.is_(None))
    return q.order_by(Topic.order_index, Topic.id)


def _workspace_files_query(
    workspace_id: int,
    *,
    topic_id: int | None = None,
    include_archived: bool = False,
    archived_only: bool = False,
):
    q = File.query.join(Topic, File.topic_id == Topic.id).filter(
        Topic.workspace_id == workspace_id,
        Topic.is_template.is_(False),
    )
    if topic_id is not None:
        q = q.filter(File.topic_id == int(topic_id))
    if archived_only:
        q = q.filter(File.archived_at.isnot(None))
    elif not include_archived:
        q = q.filter(File.archived_at.is_(None), Topic.archived_at.is_(None))
    return q.order_by(File.topic_id, File.order_index, File.id)


def _topic_rows(workspace_id: int) -> list[Topic]:
    return _workspace_topics(workspace_id, include_archived=True).all()


def _topic_names(workspace_id: int) -> dict[int, str]:
    return {t.id: (t.name or "") for t in _topic_rows(workspace_id)}


def _topic_type_names(workspace_id: int) -> dict[int, str]:
    """topic_id → English type name; empty string if the topic is untyped."""
    topics = _topic_rows(workspace_id)
    type_ids = {int(t.topic_type_id) for t in topics if t.topic_type_id}
    type_names: dict[int, str] = {}
    for type_id in type_ids:
        row = db.session.get(TopicType, type_id)
        if row is not None:
            type_names[type_id] = row.name or ""
    return {
        t.id: type_names.get(int(t.topic_type_id), "") if t.topic_type_id else ""
        for t in topics
    }


def _object_display_name(embed: ObjectEmbed) -> str:
    if embed.type == "info" and embed.information_id:
        info = db.session.get(InformationPiece, embed.information_id)
        return (info.title if info else "") or "Info"
    if embed.type == "task_list" and embed.task_list_id:
        tl = db.session.get(TaskList, embed.task_list_id)
        return (tl.title if tl else "") or "Tasks"
    if embed.type == "image":
        payload = embed.payload or {}
        return str(payload.get("caption") or "Image")
    if embed.type == "table":
        if chart_enabled(embed.payload):
            return "Graph"
        return "Table"
    return embed.type or "object"


def _object_type_label(embed: ObjectEmbed) -> str:
    if embed.type == "table" and chart_enabled(embed.payload):
        return "graph"
    return embed.type or ""


def list_entities(
    workspace_id: int,
    *,
    kind: str,
    topic_id: int | None = None,
) -> dict[str, Any]:
    """Browse the workspace. Files and objects come back grouped under their topic."""
    kind_norm = (kind or "").strip().lower()
    if kind_norm not in {"topics", "files", "objects"}:
        return {"error": "kind must be topics | files | objects"}

    if topic_id is not None:
        topic = db.session.get(Topic, int(topic_id))
        if topic is None or int(topic.workspace_id) != int(workspace_id):
            return {"error": "topic not found"}

    if kind_norm == "topics":
        return _list_topics(workspace_id, topic_id=topic_id)
    if kind_norm == "files":
        return _list_files_by_topic(workspace_id, topic_id=topic_id)
    return _list_objects_by_topic(workspace_id, topic_id=topic_id)


def _list_topics(workspace_id: int, *, topic_id: int | None) -> dict[str, Any]:
    file_rows = _workspace_files_query(
        workspace_id, topic_id=topic_id, include_archived=True
    ).all()
    counts: dict[int, int] = {}
    for f in file_rows:
        if f.archived_at is None:
            counts[f.topic_id] = counts.get(f.topic_id, 0) + 1
    topics = _topic_rows(workspace_id)
    if topic_id is not None:
        topics = [t for t in topics if t.id == int(topic_id)]
    type_names = _topic_type_names(workspace_id)
    return {
        "kind": "topics",
        "items": [
            {
                "id": t.id,
                "name": t.name,
                "topic_type": type_names.get(t.id, ""),
                "archived": t.archived_at is not None,
                "file_count": counts.get(t.id, 0),
            }
            for t in topics
            # An archived topic is noise unless it still holds files, or was asked for.
            if topic_id is not None or t.archived_at is None or counts.get(t.id)
        ],
    }


def _list_files_by_topic(workspace_id: int, *, topic_id: int | None) -> dict[str, Any]:
    rows = _workspace_files_query(
        workspace_id, topic_id=topic_id, include_archived=False
    ).all()
    files_by_topic: dict[int, list[dict[str, Any]]] = {}
    for f in rows:
        if f.archived_at is not None:
            continue
        files_by_topic.setdefault(f.topic_id, []).append(
            {
                "id": f.id,
                "name": f.name,
                "archived": False,
            }
        )
    groups = []
    type_names = _topic_type_names(workspace_id)
    for t in _topic_rows(workspace_id):
        if topic_id is not None and t.id != int(topic_id):
            continue
        files = files_by_topic.get(t.id, [])
        # An archived topic is only worth showing when it still holds files.
        if topic_id is None and t.archived_at is not None and not files:
            continue
        groups.append(
            {
                "topic_id": t.id,
                "topic": t.name,
                "topic_type": type_names.get(t.id, ""),
                "archived": t.archived_at is not None,
                "files": files,
            }
        )
    return {"kind": "files", "grouped_by": "topic", "topics": groups}


def list_archived_files(
    workspace_id: int, *, topic_id: int | None = None
) -> dict[str, Any]:
    """Archived files grouped by topic. Live files stay on ``list`` kind=files."""
    if topic_id is not None:
        topic = db.session.get(Topic, int(topic_id))
        if topic is None or int(topic.workspace_id) != int(workspace_id):
            return {"error": "topic not found"}
    rows = _workspace_files_query(
        workspace_id, topic_id=topic_id, archived_only=True
    ).all()
    files_by_topic: dict[int, list[dict[str, Any]]] = {}
    for f in rows:
        if f.archived_at is None:
            continue
        files_by_topic.setdefault(f.topic_id, []).append(
            {
                "id": f.id,
                "name": f.name,
                "archived": True,
            }
        )
    groups = []
    type_names = _topic_type_names(workspace_id)
    for t in _topic_rows(workspace_id):
        if topic_id is not None and t.id != int(topic_id):
            continue
        files = files_by_topic.get(t.id, [])
        if not files:
            continue
        groups.append(
            {
                "topic_id": t.id,
                "topic": t.name,
                "topic_type": type_names.get(t.id, ""),
                "archived": t.archived_at is not None,
                "files": files,
            }
        )
    return {"kind": "archived_files", "grouped_by": "topic", "topics": groups}


def _list_objects_by_topic(workspace_id: int, *, topic_id: int | None) -> dict[str, Any]:
    file_rows = _workspace_files_query(
        workspace_id, topic_id=topic_id, include_archived=False
    ).all()
    if not file_rows:
        return {"kind": "objects", "grouped_by": "topic", "topics": []}

    embeds = (
        ObjectEmbed.query.filter(ObjectEmbed.file_id.in_([f.id for f in file_rows]))
        .order_by(ObjectEmbed.file_id, ObjectEmbed.sort_key, ObjectEmbed.id)
        .all()
    )
    objects_by_file: dict[int, list[dict[str, Any]]] = {}
    for e in embeds:
        objects_by_file.setdefault(e.file_id, []).append(
            {
                "id": e.id,
                "type": _object_type_label(e),
                "name": _object_display_name(e),
            }
        )

    files_by_topic: dict[int, list[dict[str, Any]]] = {}
    for f in file_rows:
        objects = objects_by_file.get(f.id)
        if not objects:
            continue
        files_by_topic.setdefault(f.topic_id, []).append(
            {"file_id": f.id, "file": f.name, "objects": objects}
        )

    type_names = _topic_type_names(workspace_id)
    groups = [
        {
            "topic_id": t.id,
            "topic": t.name,
            "topic_type": type_names.get(t.id, ""),
            "files": files_by_topic[t.id],
        }
        for t in _topic_rows(workspace_id)
        if files_by_topic.get(t.id)
    ]
    return {"kind": "objects", "grouped_by": "topic", "topics": groups}


def find_file(
    workspace_id: int,
    *,
    file_id: int | None = None,
    name: str | None = None,
    topic_id: int | None = None,
) -> dict[str, Any]:
    topic_names = _topic_names(workspace_id)
    type_names = _topic_type_names(workspace_id)

    if file_id is not None:
        file = db.session.get(File, int(file_id))
        if file is None or not file_in_workspace(file, workspace_id):
            return {"error": "file not found"}
        return {
            "items": [
                {
                    "id": file.id,
                    "name": file.name,
                    "topic_id": file.topic_id,
                    "topic": topic_names.get(file.topic_id, ""),
                    "topic_type": type_names.get(file.topic_id, ""),
                    "archived": file.archived_at is not None,
                }
            ]
        }

    query = (name or "").strip().lower()
    if not query:
        return {"error": "file_id or name is required"}

    rows = _workspace_files_query(
        workspace_id, topic_id=topic_id, include_archived=True
    ).all()
    hits = []
    for f in rows:
        fname = (f.name or "").lower()
        tname = topic_names.get(f.topic_id, "").lower()
        if query in fname or query in tname:
            hits.append(
                {
                    "id": f.id,
                    "name": f.name,
                    "topic_id": f.topic_id,
                    "topic": topic_names.get(f.topic_id, ""),
                    "topic_type": type_names.get(f.topic_id, ""),
                    "archived": f.archived_at is not None,
                }
            )
    return {"items": hits}


def find_object(
    workspace_id: int,
    *,
    object_id: int | None = None,
    name: str | None = None,
    type_: str | None = None,
    topic_id: int | None = None,
) -> dict[str, Any]:
    topic_names = _topic_names(workspace_id)
    type_names = _topic_type_names(workspace_id)

    if object_id is not None:
        embed = db.session.get(ObjectEmbed, int(object_id))
        if embed is None:
            return {"error": "object not found"}
        file = db.session.get(File, embed.file_id)
        if file is None or not file_in_workspace(file, workspace_id):
            return {"error": "object not found"}
        return {
            "items": [
                {
                    "id": embed.id,
                    "type": _object_type_label(embed),
                    "name": _object_display_name(embed),
                    "file_id": embed.file_id,
                    "file": file.name,
                    "topic_id": file.topic_id,
                    "topic": topic_names.get(file.topic_id, ""),
                    "topic_type": type_names.get(file.topic_id, ""),
                }
            ]
        }

    type_filter = (type_ or "").strip().lower() or None
    if type_filter == "graph":
        type_filter = "graph"
    elif type_filter and type_filter not in {
        "task_list",
        "info",
        "table",
        "image",
        "graph",
    }:
        return {"error": "type must be task_list | info | table | graph | image"}

    name_q = (name or "").strip().lower()
    if not name_q and not type_filter and topic_id is None:
        return {"error": "object_id, or name and/or type (and optional topic_id), required"}

    file_rows = _workspace_files_query(
        workspace_id, topic_id=topic_id, include_archived=False
    ).all()
    file_ids = [f.id for f in file_rows]
    file_by_id = {f.id: f for f in file_rows}
    if not file_ids:
        return {"items": []}

    embeds = ObjectEmbed.query.filter(ObjectEmbed.file_id.in_(file_ids)).all()
    hits = []
    for e in embeds:
        label = _object_type_label(e)
        if type_filter == "graph":
            if label != "graph":
                continue
        elif type_filter == "table":
            if e.type != "table" or label == "graph":
                continue
        elif type_filter and e.type != type_filter:
            continue
        display = _object_display_name(e)
        if name_q and name_q not in display.lower():
            continue
        file = file_by_id.get(e.file_id)
        file_topic_id = file.topic_id if file is not None else None
        hits.append(
            {
                "id": e.id,
                "type": label,
                "name": display,
                "file_id": e.file_id,
                "file": file.name if file is not None else "",
                "topic_id": file_topic_id,
                "topic": topic_names.get(file_topic_id, ""),
                "topic_type": type_names.get(file_topic_id, ""),
            }
        )
    hits.sort(key=lambda r: (r.get("topic_id") or 0, r.get("file_id") or 0, r["id"]))
    return {"items": hits}


def block_index_after_agent_line(
    document_json: str,
    objects_by_id: dict[int, dict[str, Any]],
    after_line: int,
) -> int | None:
    """Map 1-based agent-text line → insert_embed_pointer block_index (None = end)."""
    if after_line <= 0:
        return 0
    text = editor_text_body(document_json)
    parts = marker_text._split_top_level_blocks(text)
    if not parts:
        return 0
    lines_seen = 0
    for i, part in enumerate(parts):
        part_agent = document_to_agent_text(
            wrap_editor_text(part),
            objects_by_id=objects_by_id,
        )
        part_lines = len(part_agent.splitlines())
        if part_lines == 0 and part.strip():
            part_lines = 1
        lines_seen += part_lines
        if lines_seen >= after_line:
            return i + 1
    return None
