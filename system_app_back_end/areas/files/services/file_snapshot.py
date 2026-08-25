"""Copy a file snippet (marker text + objects) onto another file."""

from __future__ import annotations

import copy
from datetime import datetime

from models import File, InformationPiece, ObjectEmbed, Task, TaskList, db
from areas.files.services.document_marker_text import (
    editor_text_body,
    rewrite_pointer_ids,
    wrap_editor_text,
)
from areas.files.services.document_v3 import sync_object_anchors
from areas.objects.services.delete_cascade import delete_object_embed_cascade


def append_editor_text(dest: str | None, snippet: str | None) -> str:
    dest_body = editor_text_body(dest)
    snip_body = editor_text_body(snippet)
    if not dest_body.strip():
        return wrap_editor_text(snip_body)
    if not snip_body.strip():
        return wrap_editor_text(dest_body)
    return wrap_editor_text(f"{dest_body.rstrip()}\n\n{snip_body.lstrip()}")


def apply_snippet_to_file(
    dest: File,
    snapshot: dict,
    *,
    append: bool,
) -> None:
    """Write ``snapshot`` onto ``dest``. Pointer ids in ``document_json`` are remapped."""
    if not append:
        for embed in ObjectEmbed.query.filter_by(file_id=dest.id).all():
            delete_object_embed_cascade(embed, remove_from_document=False)

    objects = snapshot.get("objects") or []
    id_map: dict[int, int] = {}
    for row in objects:
        if not isinstance(row, dict):
            continue
        old_id = row.get("id")
        clone = _embed_from_snapshot(dest.id, row)
        if old_id is not None:
            id_map[int(old_id)] = clone.id
    rewritten = rewrite_pointer_ids(snapshot.get("document_json") or "", id_map)
    if append:
        dest.document_json = append_editor_text(dest.document_json, rewritten)
    else:
        dest.document_json = rewritten
    embeds = ObjectEmbed.query.filter_by(file_id=dest.id).all()
    sync_object_anchors(dest.document_json or "", embeds)
    db.session.flush()


def _embed_from_snapshot(dest_file_id: int, row: dict) -> ObjectEmbed:
    type_ = str(row.get("type") or "info")
    task_list_id = None
    information_id = None
    if type_ == "task_list":
        blob = row.get("task_list") if isinstance(row.get("task_list"), dict) else {}
        tasks = blob.get("tasks") if blob.get("tasks") else row.get("tasks")
        new_list = TaskList(title=str(blob.get("title") or row.get("task_list_title") or ""))
        db.session.add(new_list)
        db.session.flush()
        task_list_id = new_list.id
        for i, task in enumerate(tasks or []):
            if not isinstance(task, dict):
                continue
            db.session.add(
                Task(
                    task_list_id=new_list.id,
                    title=str(task.get("title") or ""),
                    status=str(task.get("status") or "active"),
                    due_date=_parse_due(task.get("due_date")),
                    list_order_index=int(
                        task.get("list_order_index")
                        if task.get("list_order_index") is not None
                        else i
                    ),
                )
            )
    elif type_ == "info":
        blob = row.get("information") if isinstance(row.get("information"), dict) else {}
        info = InformationPiece(
            title=str(blob.get("title") or ""),
            body=str(blob.get("body") or ""),
            metadata_=copy.deepcopy(blob.get("metadata") or {}),
        )
        db.session.add(info)
        db.session.flush()
        information_id = info.id

    payload = row.get("payload")
    clone = ObjectEmbed(
        file_id=dest_file_id,
        type=type_,
        task_list_id=task_list_id,
        information_id=information_id,
        payload=copy.deepcopy(payload) if payload is not None else {},
        anchor={},
        sort_key=int(row.get("sort_key") or 0),
        diagram_x=row.get("diagram_x"),
        diagram_y=row.get("diagram_y"),
    )
    db.session.add(clone)
    db.session.flush()
    clone.anchor = {"kind": "embed", "object_id": clone.id}
    return clone


def _parse_due(raw):
    if raw in (None, ""):
        return None
    if isinstance(raw, datetime):
        return raw
    text = str(raw)
    try:
        return datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        return None
