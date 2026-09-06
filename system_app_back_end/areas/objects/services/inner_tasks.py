"""Checkbox lines stored in an info body — not `tasks` rows.

A line matching `☐` / `☑` (or legacy `- [ ]` / `- [x]` / `- ☐`) is an
inner task. Preferred storage is the glyph alone — no list dash. If that
info is the description target of a real task, unanimous inner state mirrors
the outer task (and the outer mark writes back onto every inner line).
"""

from __future__ import annotations

import re

from models import InformationPiece, Link, ObjectEmbed, Task, db
from areas.objects.services.object_graph import TASK_LINK_TYPE
from areas.objects.services.task_ops import ACTIVE, DONE, unmarked_status_for

_LINE = re.compile(r"^(\s*)(?:([-*])\s+)?(?:\[([ xX])\]|([☐☑]))\s?(.*)$")
_SYNCING = False


class InnerTaskLine:
    __slots__ = ("start", "end", "mark_start", "mark_end", "done", "title", "indent")

    def __init__(
        self,
        *,
        start: int,
        end: int,
        mark_start: int,
        mark_end: int,
        done: bool,
        title: str,
        indent: str,
    ) -> None:
        self.start = start
        self.end = end
        self.mark_start = mark_start
        self.mark_end = mark_end
        self.done = done
        self.title = title
        self.indent = indent


def parse_inner_task_lines(body: str) -> list[InnerTaskLine]:
    items: list[InnerTaskLine] = []
    offset = 0
    text = body or ""
    for raw in text.split("\n"):
        match = _LINE.match(raw)
        line_end = offset + len(raw)
        if match:
            indent = match.group(1) or ""
            bullet = match.group(2)
            box = match.group(3)
            glyph = match.group(4)
            title = match.group(5) or ""
            prefix_len = len(indent) + (2 if bullet is not None else 0)
            if box is not None:
                done = box.lower() == "x"
                mark_start = offset + prefix_len
                mark_end = mark_start + 3
            else:
                done = glyph == "☑"
                mark_start = offset + prefix_len
                mark_end = mark_start + 1
            items.append(
                InnerTaskLine(
                    start=offset,
                    end=line_end,
                    mark_start=mark_start,
                    mark_end=mark_end,
                    done=done,
                    title=title,
                    indent=indent,
                )
            )
        offset = line_end + 1
    return items


def inner_tasks_unanimous(body: str) -> bool | None:
    items = parse_inner_task_lines(body)
    if not items:
        return None
    if all(item.done for item in items):
        return True
    if all(not item.done for item in items):
        return False
    return None


def _render_line(item: InnerTaskLine, *, done: bool) -> str:
    mark = "☑" if done else "☐"
    title = item.title
    return f"{item.indent}{mark}{f' {title}' if title else ''}"


def set_all_inner_tasks(body: str, *, done: bool) -> str:
    items = parse_inner_task_lines(body)
    if not items:
        return body or ""
    by_start = {item.start: item for item in items}
    offset = 0
    out: list[str] = []
    text = body or ""
    for raw in text.split("\n"):
        item = by_start.get(offset)
        out.append(_render_line(item, done=done) if item else raw)
        offset += len(raw) + 1
    return "\n".join(out)


def toggle_inner_task_at(body: str, offset: int) -> str | None:
    items = parse_inner_task_lines(body)
    hit = next((item for item in items if item.mark_start <= offset < item.mark_end), None)
    if hit is None:
        hit = next((item for item in items if item.start <= offset <= item.end), None)
        if hit is None or not (hit.mark_start <= offset <= hit.mark_end):
            return None
    by_start = {item.start: item for item in items}
    cursor = 0
    out: list[str] = []
    text = body or ""
    for raw in text.split("\n"):
        item = by_start.get(cursor)
        if item is hit:
            out.append(_render_line(item, done=not item.done))
        else:
            out.append(raw)
        cursor += len(raw) + 1
    return "\n".join(out)


def info_embed_for_piece(info_id: int) -> ObjectEmbed | None:
    return ObjectEmbed.query.filter_by(type="info", information_id=int(info_id)).first()


def tasks_linked_to_info_object(object_id: int) -> list[Task]:
    rows = Link.query.filter_by(
        kind="description",
        source_type=TASK_LINK_TYPE,
        target_type="info",
        target_id=int(object_id),
    ).all()
    tasks = []
    for row in rows:
        task = db.session.get(Task, row.source_id)
        if task is None or task.archived_at is not None:
            continue
        tasks.append(task)
    return tasks


def infos_linked_from_task(task_id: int) -> list[InformationPiece]:
    rows = Link.query.filter_by(
        kind="description",
        source_type=TASK_LINK_TYPE,
        source_id=int(task_id),
        target_type="info",
    ).all()
    pieces = []
    for row in rows:
        embed = db.session.get(ObjectEmbed, row.target_id)
        if embed is None or embed.information_id is None:
            continue
        info = db.session.get(InformationPiece, embed.information_id)
        if info is None:
            continue
        pieces.append(info)
    return pieces


def sync_outer_tasks_from_info(info: InformationPiece) -> None:
    """All inner done → outer done; all inner active → outer active; mixed → skip."""
    global _SYNCING
    if _SYNCING:
        return
    embed = info_embed_for_piece(info.id)
    if embed is None:
        return
    verdict = inner_tasks_unanimous(info.body or "")
    if verdict is None:
        return
    _SYNCING = True
    try:
        for task in tasks_linked_to_info_object(embed.id):
            if task.status not in (ACTIVE, DONE):
                continue
            if verdict and task.status != DONE:
                task.status = DONE
            elif not verdict and task.status == DONE:
                task.status = unmarked_status_for(task)
    finally:
        _SYNCING = False


def sync_inner_tasks_from_outer(task: Task) -> None:
    """Outer done → every inner done; outer active → every inner active."""
    global _SYNCING
    if _SYNCING:
        return
    if not getattr(task, "id", None):
        return
    if task.status not in (ACTIVE, DONE):
        return
    done = task.status == DONE
    _SYNCING = True
    try:
        for info in infos_linked_from_task(task.id):
            next_body = set_all_inner_tasks(info.body or "", done=done)
            if next_body != (info.body or ""):
                info.body = next_body
    finally:
        _SYNCING = False
