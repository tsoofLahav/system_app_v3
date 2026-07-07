"""Tests for part-aware unit flattening."""

from services.unit_mapper import (
    extract_part_names,
    flatten_file_by_parts_for_ai,
)


def test_extract_part_names_from_headers():
    units = [
        {"id": "h1", "kind": "header", "text": "Backend"},
        {"id": "p1", "kind": "paragraph", "text": "Intro"},
        {"id": "h2", "kind": "header", "text": "Frontend"},
    ]
    assert extract_part_names(units) == ["Backend", "Frontend"]


def test_flatten_file_by_parts_for_ai_groups_units():
    units = [
        {"id": "h1", "kind": "header", "text": "API"},
        {"id": "i1", "kind": "list_item", "text": "Define contracts"},
        {"id": "h2", "kind": "header", "text": "Mobile"},
        {"id": "i2", "kind": "list_item", "text": "Build shell"},
    ]
    flattened = flatten_file_by_parts_for_ai(units, "Plan")

    assert 'PART LIST: "API" | "Mobile"' in flattened
    assert "--- PART: API ---" in flattened
    assert "[i1] Define contracts" in flattened
    assert "--- PART: Mobile ---" in flattened
    assert "[i2] Build shell" in flattened
