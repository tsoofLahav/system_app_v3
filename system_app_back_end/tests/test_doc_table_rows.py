"""Tests for shared doc table row helpers."""

from services.doc_table_rows import (
    DEFAULT_TABLE_HEADER,
    build_rows_with_insert,
    looks_like_header_row,
)


def test_looks_like_header_row():
    assert looks_like_header_row(["Date", "Entry"]) is True
    assert looks_like_header_row(["2026-07-06", "note"]) is False


def test_build_rows_with_insert_inserts_below_header():
    rows = build_rows_with_insert(
        [DEFAULT_TABLE_HEADER[:], ["", ""]],
        "2026-07-06",
        "Daily note",
    )

    assert rows[0] == ["Date", "Entry"]
    assert rows[1] == ["2026-07-06", "Daily note"]


def test_build_rows_allows_multiple_entries_same_date():
    rows = build_rows_with_insert(
        [DEFAULT_TABLE_HEADER[:], ["", ""]],
        "2026-07-06",
        "first",
    )
    rows = build_rows_with_insert(rows, "2026-07-06", "second")

    assert rows[1] == ["2026-07-06", "second"]
    assert rows[2] == ["2026-07-06", "first"]
