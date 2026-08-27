"""Agent `connect` tool — related info↔info, or description (text → info).

Related is the objects-map edge. Description underlines a span on a host
(info / task / table / task-list title) and, when the host is an info, also
upserts related so the map gets that edge.
"""

from __future__ import annotations

from typing import Any

from models import File, InformationPiece, Link, ObjectEmbed, Task, TaskList, db
from areas.objects.services.object_graph import (
    TASK_LINK_TYPE,
    ensure_related_info_link,
    file_id_for_task,
    find_related_link,
    info_peer_dict,
    normalize_description_anchor,
    related_requires_info,
    workspace_id_for_task,
)
from areas.production_agent.services.browse_tools import file_in_workspace
from areas.production_agent.services.write_tools import WriteMode


def _blank(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def _compose_info_text(title: str, body: str) -> str:
    title = title or ""
    body = body or ""
    if not title and not body:
        return ""
    if not body:
        return title
    return f"{title}\n{body}"


def _embed_segment_prefix(object_id: int) -> str:
    return f"embed:{object_id}"


def _find_span(haystack: str, needle: str) -> tuple[int, int] | None:
    if not needle:
        return None
    start = haystack.find(needle)
    if start < 0:
        return None
    return start, start + len(needle)


def _object_in_workspace(embed: ObjectEmbed, workspace_id: int) -> bool:
    file = db.session.get(File, embed.file_id)
    if file is None:
        return False
    return file_in_workspace(file, workspace_id)


def _archived_host_error(file: File | None) -> dict[str, Any] | None:
    if file is None:
        return None
    if file.archived_at is not None:
        return {"error": "archived files are read-only", "tool": "connect"}
    return None


def _cell_text(cell: Any) -> str:
    if isinstance(cell, dict):
        return str(cell.get("text") or "")
    return str(cell or "")


def _table_hits(embed: ObjectEmbed, needle: str) -> list[tuple[str, str, int, int]]:
    """(segment_id, cell_text, start, end) for each cell that contains needle."""
    payload = embed.payload if isinstance(embed.payload, dict) else {}
    rows = payload.get("rows")
    if not isinstance(rows, list):
        return []
    prefix = _embed_segment_prefix(embed.id)
    hits: list[tuple[str, str, int, int]] = []
    for row_i, row in enumerate(rows):
        if not isinstance(row, list):
            continue
        for col_i, cell in enumerate(row):
            text = _cell_text(cell)
            span = _find_span(text, needle)
            if span is None:
                continue
            hits.append((f"{prefix}#c{row_i}:{col_i}", text, span[0], span[1]))
    return hits


def _host_span_for_object(
    embed: ObjectEmbed, *, text: str, segment_id: str | None
) -> tuple[dict[str, Any], dict[str, Any] | None]:
    needle = text.strip()
    if not needle:
        return {}, {"error": "text required to find the span", "tool": "connect"}

    if segment_id:
        haystack, inferred = _text_for_segment(embed, segment_id)
        if haystack is None:
            return {}, {
                "error": "segment_id does not match this object",
                "tool": "connect",
            }
        span = _find_span(haystack, needle)
        if span is None:
            return {}, {
                "error": "text not found in that segment",
                "tool": "connect",
            }
        return (
            {
                "segment_id": inferred,
                "start": span[0],
                "end": span[1],
                "file_id": embed.file_id,
            },
            None,
        )

    if embed.type == "info":
        info = (
            db.session.get(InformationPiece, embed.information_id)
            if embed.information_id
            else None
        )
        haystack = _compose_info_text(
            (info.title if info else "") or "",
            (info.body if info else "") or "",
        )
        span = _find_span(haystack, needle)
        if span is None:
            return {}, {"error": "text not found in that info", "tool": "connect"}
        return (
            {
                "segment_id": f"{_embed_segment_prefix(embed.id)}#infoText",
                "start": span[0],
                "end": span[1],
                "file_id": embed.file_id,
            },
            None,
        )

    if embed.type == "task_list":
        title = ""
        if embed.task_list_id:
            task_list = db.session.get(TaskList, embed.task_list_id)
            title = (task_list.title if task_list else "") or ""
        span = _find_span(title, needle)
        if span is None:
            return {}, {
                "error": "text not found in the task-list title; "
                "use source_task_id for a task row",
                "tool": "connect",
            }
        return (
            {
                "segment_id": f"{_embed_segment_prefix(embed.id)}#taskListTitle",
                "start": span[0],
                "end": span[1],
                "file_id": embed.file_id,
            },
            None,
        )

    if embed.type == "table":
        hits = _table_hits(embed, needle)
        if not hits:
            return {}, {"error": "text not found in that table", "tool": "connect"}
        if len(hits) > 1:
            return {}, {
                "error": "text matches more than one cell; pass segment_id",
                "tool": "connect",
                "matches": [h[0] for h in hits],
            }
        segment, _, start, end = hits[0]
        return (
            {
                "segment_id": segment,
                "start": start,
                "end": end,
                "file_id": embed.file_id,
            },
            None,
        )

    caption = ""
    if isinstance(embed.payload, dict):
        caption = str(embed.payload.get("caption") or "")
    span = _find_span(caption, needle)
    if span is None:
        return {}, {
            "error": "text not found on that object",
            "tool": "connect",
        }
    return (
        {
            "segment_id": f"{_embed_segment_prefix(embed.id)}#caption",
            "start": span[0],
            "end": span[1],
            "file_id": embed.file_id,
        },
        None,
    )


def _text_for_segment(embed: ObjectEmbed, segment_id: str) -> tuple[str | None, str]:
    prefix = _embed_segment_prefix(embed.id)
    if segment_id == f"{prefix}#infoText" or segment_id.endswith("#infoText"):
        info = (
            db.session.get(InformationPiece, embed.information_id)
            if embed.information_id
            else None
        )
        return (
            _compose_info_text(
                (info.title if info else "") or "",
                (info.body if info else "") or "",
            ),
            f"{prefix}#infoText",
        )
    if segment_id == f"{prefix}#taskListTitle" or segment_id.endswith(
        "#taskListTitle"
    ):
        title = ""
        if embed.task_list_id:
            task_list = db.session.get(TaskList, embed.task_list_id)
            title = (task_list.title if task_list else "") or ""
        return title, f"{prefix}#taskListTitle"
    cell_prefix = f"{prefix}#c"
    if segment_id.startswith(cell_prefix):
        rest = segment_id[len(cell_prefix) :]
        parts = rest.split(":", 1)
        if len(parts) != 2:
            return None, segment_id
        try:
            row_i = int(parts[0])
            col_i = int(parts[1])
        except ValueError:
            return None, segment_id
        payload = embed.payload if isinstance(embed.payload, dict) else {}
        rows = payload.get("rows")
        if not isinstance(rows, list) or row_i < 0 or row_i >= len(rows):
            return None, segment_id
        row = rows[row_i]
        if not isinstance(row, list) or col_i < 0 or col_i >= len(row):
            return None, segment_id
        return _cell_text(row[col_i]), segment_id
    return None, segment_id


def _load_info_target(
    *, workspace_id: int, target_object_id: int | None
) -> tuple[ObjectEmbed | None, dict[str, Any] | None]:
    if not target_object_id:
        return None, {"error": "target_object_id required", "tool": "connect"}
    target = db.session.get(ObjectEmbed, int(target_object_id))
    if target is None:
        return None, {"error": "target object not found", "tool": "connect"}
    if not _object_in_workspace(target, workspace_id):
        return None, {"error": "target out of workspace", "tool": "connect"}
    if target.type != "info":
        return None, {
            "error": "target must be an info object",
            "tool": "connect",
        }
    file = db.session.get(File, target.file_id)
    archived = _archived_host_error(file)
    if archived:
        return None, archived
    return target, None


def _connect_related(
    *,
    workspace_id: int,
    write_mode: WriteMode,
    source_object_id: int | None,
    target_object_id: int | None,
) -> dict[str, Any]:
    if not source_object_id:
        return {"error": "source_object_id required for related", "tool": "connect"}
    source = db.session.get(ObjectEmbed, int(source_object_id))
    if source is None:
        return {"error": "source object not found", "tool": "connect"}
    if not _object_in_workspace(source, workspace_id):
        return {"error": "source out of workspace", "tool": "connect"}
    file = db.session.get(File, source.file_id)
    archived = _archived_host_error(file)
    if archived:
        return archived
    target, err = _load_info_target(
        workspace_id=workspace_id, target_object_id=target_object_id
    )
    if err:
        return err
    assert target is not None
    if source.id == target.id:
        return {"error": "cannot link an object to itself", "tool": "connect"}
    if not related_requires_info(source.type, target.type):
        return {"error": "related links require info endpoints", "tool": "connect"}

    existing = find_related_link(workspace_id, source.id, target.id)
    if write_mode == "notify_only":
        return {
            "tool": "connect",
            "action": "related",
            "applied": False,
            "source_object_id": source.id,
            "target_object_id": target.id,
            "link_id": existing.id if existing is not None else None,
        }

    if existing is None:
        existing = ensure_related_info_link(workspace_id, source, target)
        db.session.flush()
    return {
        "tool": "connect",
        "action": "related",
        "applied": write_mode == "direct_apply",
        "source_object_id": source.id,
        "target_object_id": target.id,
        "link_id": existing.id,
        "kind": "related",
    }


def _connect_description(
    *,
    workspace_id: int,
    write_mode: WriteMode,
    source_object_id: int | None,
    source_task_id: int | None,
    target_object_id: int | None,
    text: str,
    segment_id: str | None,
) -> dict[str, Any]:
    if not source_task_id and not source_object_id:
        return {
            "error": "source_object_id or source_task_id required for description",
            "tool": "connect",
        }
    target, err = _load_info_target(
        workspace_id=workspace_id, target_object_id=target_object_id
    )
    if err:
        return err
    assert target is not None

    if source_task_id:
        task = db.session.get(Task, int(source_task_id))
        if task is None or task.archived_at is not None:
            return {"error": "task not found", "tool": "connect"}
        task_ws = workspace_id_for_task(task)
        if task_ws is None or int(task_ws) != int(workspace_id):
            return {"error": "task out of workspace", "tool": "connect"}
        host_file_id = file_id_for_task(task)
        if host_file_id is not None:
            file = db.session.get(File, host_file_id)
            archived = _archived_host_error(file)
            if archived:
                return archived
        haystack = task.title or ""
        span = _find_span(haystack, text.strip())
        if span is None:
            return {"error": "text not found in that task title", "tool": "connect"}
        raw_anchor = {
            "segment_id": f"task:{task.id}",
            "start": span[0],
            "end": span[1],
        }
        if host_file_id is not None:
            raw_anchor["file_id"] = host_file_id
        try:
            anchor = normalize_description_anchor(raw_anchor)
        except ValueError as exc:
            return {"error": str(exc), "tool": "connect"}

        if write_mode == "notify_only":
            return {
                "tool": "connect",
                "action": "description",
                "applied": False,
                "source_task_id": task.id,
                "target_object_id": target.id,
                "anchor": anchor,
            }

        link = Link(
            workspace_id=workspace_id,
            source_type=TASK_LINK_TYPE,
            source_id=task.id,
            target_type="info",
            target_id=target.id,
            kind="description",
            anchor=anchor,
        )
        db.session.add(link)
        db.session.flush()
        data = link.to_dict()
        data["peer"] = info_peer_dict(target, target.id)
        return {
            "tool": "connect",
            "action": "description",
            "applied": write_mode == "direct_apply",
            "source_task_id": task.id,
            "target_object_id": target.id,
            "link_id": link.id,
            "kind": "description",
            "anchor": anchor,
        }

    if not source_object_id:
        return {
            "error": "source_object_id or source_task_id required for description",
            "tool": "connect",
        }
    source = db.session.get(ObjectEmbed, int(source_object_id))
    if source is None:
        return {"error": "source object not found", "tool": "connect"}
    if not _object_in_workspace(source, workspace_id):
        return {"error": "source out of workspace", "tool": "connect"}
    file = db.session.get(File, source.file_id)
    archived = _archived_host_error(file)
    if archived:
        return archived
    if source.id == target.id:
        return {"error": "cannot link an object to itself", "tool": "connect"}

    anchor_raw, span_err = _host_span_for_object(
        source, text=text, segment_id=segment_id
    )
    if span_err:
        return span_err
    try:
        anchor = normalize_description_anchor(anchor_raw)
    except ValueError as exc:
        return {"error": str(exc), "tool": "connect"}

    if write_mode == "notify_only":
        return {
            "tool": "connect",
            "action": "description",
            "applied": False,
            "source_object_id": source.id,
            "target_object_id": target.id,
            "anchor": anchor,
        }

    link = Link(
        workspace_id=workspace_id,
        source_type=source.type,
        source_id=source.id,
        target_type="info",
        target_id=target.id,
        kind="description",
        anchor=anchor,
    )
    db.session.add(link)
    related_id = None
    if source.type == "info":
        related = ensure_related_info_link(workspace_id, source, target)
        db.session.flush()
        related_id = related.id
    else:
        db.session.flush()
    return {
        "tool": "connect",
        "action": "description",
        "applied": write_mode == "direct_apply",
        "source_object_id": source.id,
        "target_object_id": target.id,
        "link_id": link.id,
        "kind": "description",
        "anchor": anchor,
        "related_link_id": related_id,
    }


def connect_tool(
    *,
    workspace_id: int,
    action: str,
    write_mode: WriteMode,
    source_object_id: int | None = None,
    source_task_id: int | None = None,
    target_object_id: int | None = None,
    text: str = "",
    segment_id: str = "",
) -> dict[str, Any]:
    kind = (action or "").strip().lower()
    if kind == "related":
        return _connect_related(
            workspace_id=workspace_id,
            write_mode=write_mode,
            source_object_id=source_object_id,
            target_object_id=target_object_id,
        )
    if kind == "description":
        return _connect_description(
            workspace_id=workspace_id,
            write_mode=write_mode,
            source_object_id=source_object_id,
            source_task_id=source_task_id,
            target_object_id=target_object_id,
            text=text or "",
            segment_id=_blank(segment_id),
        )
    return {
        "error": 'action must be "related" or "description"',
        "tool": "connect",
    }
