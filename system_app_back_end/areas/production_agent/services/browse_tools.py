"""Workspace browse tools: list / find_file / find_object."""

from __future__ import annotations

from typing import Any

from models import (
    File,
    InformationPiece,
    ObjectEmbed,
    TaskList,
    Topic,
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
    q = Topic.query.filter_by(workspace_id=workspace_id)
    if not include_archived:
        q = q.filter(Topic.archived_at.is_(None))
    return q.order_by(Topic.order_index, Topic.id)


def _workspace_files_query(
    workspace_id: int,
    *,
    topic_id: int | None = None,
    include_archived: bool = False,
):
    q = File.query.join(Topic, File.topic_id == Topic.id).filter(
        Topic.workspace_id == workspace_id
    )
    if topic_id is not None:
        q = q.filter(File.topic_id == int(topic_id))
    if not include_archived:
        q = q.filter(File.archived_at.is_(None), Topic.archived_at.is_(None))
    return q.order_by(File.topic_id, File.order_index, File.id)


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
    kind_norm = (kind or "").strip().lower()
    if kind_norm not in {"topics", "files", "objects"}:
        return {"error": "kind must be topics | files | objects"}

    if kind_norm == "topics":
        if topic_id is not None:
            topic = db.session.get(Topic, int(topic_id))
            if topic is None or int(topic.workspace_id) != int(workspace_id):
                return {"error": "topic not found"}
            return {
                "kind": "topics",
                "items": [
                    {
                        "id": topic.id,
                        "name": topic.name,
                        "archived": topic.archived_at is not None,
                    }
                ],
            }
        items = [
            {
                "id": t.id,
                "name": t.name,
                "archived": t.archived_at is not None,
            }
            for t in _workspace_topics(workspace_id).all()
        ]
        return {"kind": "topics", "items": items}

    if kind_norm == "files":
        rows = _workspace_files_query(
            workspace_id, topic_id=topic_id, include_archived=True
        ).all()
        return {
            "kind": "files",
            "items": [
                {
                    "id": f.id,
                    "name": f.name,
                    "topic_id": f.topic_id,
                    "archived": f.archived_at is not None,
                }
                for f in rows
            ],
        }

    # objects
    file_q = _workspace_files_query(
        workspace_id, topic_id=topic_id, include_archived=False
    )
    file_rows = file_q.all()
    file_ids = [f.id for f in file_rows]
    topic_by_file = {f.id: f.topic_id for f in file_rows}
    if not file_ids:
        return {"kind": "objects", "items": []}
    embeds = (
        ObjectEmbed.query.filter(ObjectEmbed.file_id.in_(file_ids))
        .order_by(ObjectEmbed.file_id, ObjectEmbed.sort_key, ObjectEmbed.id)
        .all()
    )
    return {
        "kind": "objects",
        "items": [
            {
                "id": e.id,
                "type": _object_type_label(e),
                "name": _object_display_name(e),
                "file_id": e.file_id,
                "topic_id": topic_by_file.get(e.file_id),
            }
            for e in embeds
        ],
    }


def find_file(
    workspace_id: int,
    *,
    file_id: int | None = None,
    name: str | None = None,
    topic_id: int | None = None,
) -> dict[str, Any]:
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
    topic_names = {
        t.id: (t.name or "")
        for t in _workspace_topics(workspace_id, include_archived=True).all()
    }
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
                    "topic_id": file.topic_id,
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
    topic_by_file = {f.id: f.topic_id for f in file_rows}
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
        hits.append(
            {
                "id": e.id,
                "type": label,
                "name": display,
                "file_id": e.file_id,
                "topic_id": topic_by_file.get(e.file_id),
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
