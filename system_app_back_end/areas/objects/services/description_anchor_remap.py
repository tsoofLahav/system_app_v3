"""Shift description-link spans when host text changes.

Same prefix/suffix diff as the file editor (`remapOffsetRange`): characters
inserted immediately before a range stay outside it, so the underline follows
the original glyphs. Used on agent apply — user typing remaps in the field.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from models import Link, db
from areas.objects.services.object_graph import (
    TASK_LINK_TYPE,
    patch_description_anchor,
)


@dataclass(frozen=True)
class TextEditDiff:
    replace_start: int
    removed_length: int
    inserted_length: int


def text_edit_diff(old_text: str, new_text: str) -> TextEditDiff:
    prefix = 0
    max_prefix = min(len(old_text), len(new_text))
    while prefix < max_prefix and old_text[prefix] == new_text[prefix]:
        prefix += 1
    old_suffix = len(old_text)
    new_suffix = len(new_text)
    while (
        old_suffix > prefix
        and new_suffix > prefix
        and old_text[old_suffix - 1] == new_text[new_suffix - 1]
    ):
        old_suffix -= 1
        new_suffix -= 1
    return TextEditDiff(
        replace_start=prefix,
        removed_length=old_suffix - prefix,
        inserted_length=new_suffix - prefix,
    )


def remap_offset_range(
    start: int,
    end: int,
    old_text: str,
    new_text: str,
) -> tuple[int, int] | None:
    if old_text == new_text:
        if end <= start:
            return None
        return start, end
    return remap_offset_range_with_diff(
        start, end, text_edit_diff(old_text, new_text)
    )


def remap_offset_range_with_diff(
    start: int,
    end: int,
    diff: TextEditDiff,
) -> tuple[int, int] | None:
    edit_start = diff.replace_start
    edit_end = edit_start + diff.removed_length
    delta = diff.inserted_length - diff.removed_length

    def map_point(offset: int, *, is_end: bool) -> int:
        if offset < edit_start:
            return offset
        if offset >= edit_end:
            return offset + delta
        return edit_start + diff.inserted_length if is_end else edit_start

    new_start = map_point(start, is_end=False)
    new_end = map_point(end, is_end=True)
    if new_end <= new_start:
        return None
    return new_start, new_end


def compose_info_text(title: str, body: str) -> str:
    title = title or ""
    body = body or ""
    if not title and not body:
        return ""
    if not body:
        return title
    return f"{title}\n{body}"


def remap_description_links_for_text(
    *,
    source_type: str,
    source_id: int,
    old_text: str,
    new_text: str,
    segment_id: str | None = None,
) -> None:
    """Patch (or drop) description spans on one host after its text changed."""
    if old_text == new_text:
        return
    rows = (
        Link.query.filter(
            Link.kind == "description",
            Link.source_type == source_type,
            Link.source_id == int(source_id),
            Link.target_type == "info",
        ).all()
    )
    to_delete: list[Link] = []
    for link in rows:
        anchor = link.anchor if isinstance(link.anchor, dict) else {}
        if segment_id is not None and str(anchor.get("segment_id") or "") != segment_id:
            continue
        try:
            start = int(anchor.get("start", 0))
            end = int(anchor.get("end", 0))
        except (TypeError, ValueError):
            continue
        mapped = remap_offset_range(start, end, old_text, new_text)
        if mapped is None:
            to_delete.append(link)
            continue
        new_start, new_end = mapped
        if new_start == start and new_end == end:
            continue
        patch_description_anchor(
            link, {**anchor, "start": new_start, "end": new_end}
        )
    for link in to_delete:
        db.session.delete(link)


def remap_table_description_links(
    embed_id: int,
    old_payload: dict[str, Any] | None,
    new_payload: dict[str, Any] | None,
) -> None:
    old_rows = _payload_rows(old_payload)
    new_rows = _payload_rows(new_payload)
    rows = Link.query.filter(
        Link.kind == "description",
        Link.source_id == int(embed_id),
        Link.target_type == "info",
    ).all()
    to_delete: list[Link] = []
    for link in rows:
        anchor = link.anchor if isinstance(link.anchor, dict) else {}
        parsed = _parse_table_cell_segment(str(anchor.get("segment_id") or ""))
        if parsed is None:
            continue
        _, row_i, col_i = parsed
        old_text = _cell_text(old_rows, row_i, col_i)
        new_text = _cell_text(new_rows, row_i, col_i)
        if new_text is None:
            to_delete.append(link)
            continue
        if old_text is None:
            continue
        try:
            start = int(anchor.get("start", 0))
            end = int(anchor.get("end", 0))
        except (TypeError, ValueError):
            continue
        mapped = remap_offset_range(start, end, old_text, new_text)
        if mapped is None:
            to_delete.append(link)
            continue
        new_start, new_end = mapped
        if new_start == start and new_end == end:
            continue
        patch_description_anchor(
            link, {**anchor, "start": new_start, "end": new_end}
        )
    for link in to_delete:
        db.session.delete(link)


def _payload_rows(payload: dict[str, Any] | None) -> list:
    if not isinstance(payload, dict):
        return []
    rows = payload.get("rows")
    return rows if isinstance(rows, list) else []


def _cell_text(rows: list, row_i: int, col_i: int) -> str | None:
    if row_i < 0 or col_i < 0 or row_i >= len(rows):
        return None
    row = rows[row_i]
    if not isinstance(row, list) or col_i >= len(row):
        return None
    cell = row[col_i]
    if isinstance(cell, dict):
        return str(cell.get("text") or "")
    return str(cell or "")


def _parse_table_cell_segment(segment_id: str) -> tuple[str, int, int] | None:
    marker = "#c"
    idx = segment_id.rfind(marker)
    if idx < 0:
        return None
    rest = segment_id[idx + len(marker) :]
    parts = rest.split(":", 1)
    if len(parts) != 2:
        return None
    try:
        return segment_id[:idx], int(parts[0]), int(parts[1])
    except ValueError:
        return None


def task_title_segment_id(task_id: int) -> str:
    return f"{TASK_LINK_TYPE}:{int(task_id)}"
