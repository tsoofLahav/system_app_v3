"""Agent `views` tool — list views/sections, or assign a task to one view.

A task belongs to at most one view. Assigning replaces any previous membership.
Uncategorized is not a named section: empty ``section_name`` is that leftover bucket.
"""

from __future__ import annotations

from typing import Any

from models import ObjectEmbed, Task, View, ViewTaskMembership, db
from shared.helpers import active_query
from areas.objects.services.object_graph import workspace_id_for_task
from areas.production_agent.services.write_tools import WriteMode


def layout_sections(config: Any) -> list[dict[str, Any]]:
    raw = config.get("sections") if isinstance(config, dict) else None
    if not isinstance(raw, list):
        return []
    out: list[dict[str, Any]] = []
    for index, item in enumerate(raw):
        if not isinstance(item, dict):
            continue
        name = str(item.get("name") or "").strip()
        if not name:
            continue
        entry: dict[str, Any] = {
            "name": name,
            "order": item.get("order", index),
        }
        flag = item.get("flag")
        if flag:
            entry["flag"] = flag
        out.append(entry)
    out.sort(key=lambda row: (int(row.get("order") or 0), str(row["name"])))
    return out


def list_views(workspace_id: int) -> dict[str, Any]:
    rows = (
        active_query(View)
        .filter_by(workspace_id=workspace_id)
        .order_by(View.order_index, View.id)
        .all()
    )
    views = []
    for view in rows:
        views.append(
            {
                "view_id": view.id,
                "name": view.name,
                "sections": layout_sections(view.layout_config),
            }
        )
    return {
        "tool": "views",
        "action": "list",
        "views": views,
        "uncategorized": (
            "Leftover bucket for tasks with no section_name — not a named "
            "section. Assign with section_name \"\"."
        ),
    }


def _blank(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def _resolve_task(
    *,
    workspace_id: int,
    task_id: int | None,
    object_id: int | None,
    title: str | None,
) -> tuple[Task | None, dict[str, Any] | None]:
    if task_id:
        task = db.session.get(Task, int(task_id))
        if task is None or task.archived_at is not None:
            return None, {"error": "task not found", "tool": "views"}
        if workspace_id_for_task(task) not in (None, workspace_id):
            return None, {"error": "task out of workspace", "tool": "views"}
        return task, None

    if not object_id:
        return None, {
            "error": "task_id or object_id (the [TASK_LIST] id) + title required",
            "tool": "views",
        }
    embed = db.session.get(ObjectEmbed, int(object_id))
    if (
        embed is None
        or embed.type != "task_list"
        or not embed.task_list_id
    ):
        return None, {"error": "object_id must be a task_list embed", "tool": "views"}
    needle = (title or "").strip().casefold()
    if not needle:
        return None, {
            "error": "title required when using object_id",
            "tool": "views",
        }
    matches = [
        t
        for t in Task.query.filter_by(task_list_id=embed.task_list_id).all()
        if t.archived_at is None and (t.title or "").strip().casefold() == needle
    ]
    if not matches:
        return None, {"error": "no task with that title in the list", "tool": "views"}
    if len(matches) > 1:
        return None, {
            "error": "several tasks share that title; pass task_id",
            "tool": "views",
            "task_ids": [t.id for t in matches],
        }
    task = matches[0]
    if workspace_id_for_task(task) not in (None, workspace_id):
        return None, {"error": "task out of workspace", "tool": "views"}
    return task, None


def _canonical_section(view: View, section_name: str | None) -> tuple[str | None, dict | None]:
    if section_name is None:
        return None, None
    lowered = section_name.casefold()
    if lowered in {"uncategorized", "no category", "no section"}:
        return None, None
    sections = layout_sections(view.layout_config)
    for row in sections:
        if str(row["name"]).casefold() == lowered:
            return str(row["name"]), None
    names = [str(row["name"]) for row in sections]
    return None, {
        "error": "unknown section; call views action=list",
        "tool": "views",
        "sections": names,
        "uncategorized": 'use section_name ""',
    }


def assign_view(
    *,
    workspace_id: int,
    write_mode: WriteMode,
    task_id: int | None,
    object_id: int | None,
    title: str | None,
    view_id: int | None,
    section_name: str | None,
) -> dict[str, Any]:
    task, err = _resolve_task(
        workspace_id=workspace_id,
        task_id=task_id,
        object_id=object_id,
        title=title,
    )
    if err:
        return err
    assert task is not None

    assigned_view: View | None = None
    assigned_section: str | None = None
    if view_id:
        assigned_view = db.session.get(View, int(view_id))
        if assigned_view is None or assigned_view.archived_at is not None:
            return {"error": "view not found", "tool": "views"}
        if int(assigned_view.workspace_id) != int(workspace_id):
            return {"error": "view out of workspace", "tool": "views"}
        assigned_section, section_err = _canonical_section(
            assigned_view, section_name
        )
        if section_err:
            return section_err

    if write_mode == "notify_only":
        return {
            "tool": "views",
            "action": "assign",
            "applied": False,
            "task_id": task.id,
            "view_id": assigned_view.id if assigned_view else None,
            "section_name": assigned_section,
        }

    ViewTaskMembership.query.filter_by(task_id=task.id).delete(
        synchronize_session=False
    )
    if assigned_view is not None:
        count = ViewTaskMembership.query.filter_by(view_id=assigned_view.id).count()
        db.session.add(
            ViewTaskMembership(
                view_id=assigned_view.id,
                task_id=task.id,
                section_name=assigned_section,
                order_index=count,
                topic_order_index=count,
            )
        )

    db.session.flush()
    from areas.objects.services.task_ops import sync_status_with_memberships

    sync_status_with_memberships(task)
    return {
        "tool": "views",
        "action": "assign",
        "applied": write_mode == "direct_apply",
        "task_id": task.id,
        "view_id": assigned_view.id if assigned_view else None,
        "section_name": assigned_section,
    }


def views_tool(
    *,
    workspace_id: int,
    action: str,
    write_mode: WriteMode,
    task_id: int | None = None,
    object_id: int | None = None,
    title: str | None = None,
    view_id: int | None = None,
    section_name: str | None = None,
) -> dict[str, Any]:
    kind = (action or "").strip().lower()
    if kind == "list":
        return list_views(workspace_id)
    if kind == "assign":
        return assign_view(
            workspace_id=workspace_id,
            write_mode=write_mode,
            task_id=task_id,
            object_id=object_id,
            title=title,
            view_id=view_id,
            section_name=_blank(section_name),
        )
    return {
        "error": 'action must be "list" or "assign"',
        "tool": "views",
    }
