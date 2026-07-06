"""Shared helpers for inserting dated rows into doc table blocks."""

from __future__ import annotations

import re

from sqlalchemy.orm.attributes import flag_modified

_ISO_DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
DEFAULT_TABLE_HEADER = ["Date", "Entry"]


def looks_like_header_row(row: list[str]) -> bool:
    if not row:
        return False
    first = str(row[0]).strip()
    if _ISO_DATE_RE.match(first):
        return False
    second = str(row[1]).strip() if len(row) > 1 else ""
    return bool(first) or bool(second)


def build_rows_with_insert(rows: list, entry_date: str, text: str) -> list[list[str]]:
    if not isinstance(rows, list):
        rows = []

    normalized_rows = []
    for row in rows:
        if isinstance(row, list):
            normalized_rows.append([str(cell) for cell in row])
        else:
            normalized_rows.append([str(row)])

    if not normalized_rows:
        normalized_rows = [DEFAULT_TABLE_HEADER[:], ["", ""]]
    elif len(normalized_rows[0]) < 2:
        first = normalized_rows[0]
        normalized_rows[0] = [
            str(first[0]) if first else "",
            str(first[1]) if len(first) > 1 else "",
        ]

    insert_index = 1 if looks_like_header_row(normalized_rows[0]) else 0
    normalized_rows.insert(insert_index, [entry_date, text])
    return normalized_rows


def insert_row_into_table_block(table_block, entry_date: str, text: str) -> None:
    rows = (table_block.content or {}).get("rows")
    table_block.content = {
        "rows": build_rows_with_insert(rows, entry_date, text),
    }
    flag_modified(table_block, "content")
