"""Tests for doc row append helpers used during project finalize."""

from services.doc_table_rows import build_rows_with_insert, DEFAULT_TABLE_HEADER


def test_doc_append_inserts_multiple_rows_below_header():
    rows = [DEFAULT_TABLE_HEADER[:], ["", ""]]
    rows = build_rows_with_insert(rows, "2026-07-14", "First entry")
    rows = build_rows_with_insert(rows, "2026-07-14", "Second entry")

    assert rows[0] == ["Date", "Entry"]
    assert rows[1] == ["2026-07-14", "Second entry"]
    assert rows[2] == ["2026-07-14", "First entry"]
