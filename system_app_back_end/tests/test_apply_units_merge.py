"""Tests for merge + apply preserving add_after inserts."""

from types import SimpleNamespace

from services.diff_engine import build_document_change_set, merge_document


def test_build_document_change_set_add_after_inherits_block_id():
    units = [
        {"id": "h1", "kind": "header", "text": "Part A", "block_id": 1},
        {
            "id": "i1",
            "kind": "list_item",
            "text": "First",
            "block_id": 10,
            "path": ["items", 0],
        },
        {
            "id": "i2",
            "kind": "list_item",
            "text": "Second",
            "block_id": 10,
            "path": ["items", 1],
        },
    ]
    doc = build_document_change_set(
        "execution",
        "Execution",
        units,
        [{"op": "add_after", "unit_id": "i1", "text": "Inserted"}],
        id_prefix="execution:parta",
    )
    change = doc["changes"][0]
    assert change["action"] == "add_after"
    assert change["new_unit"]["block_id"] == 10
    assert change["new_unit"]["path"] == ["items", 1]


def test_merge_add_after_preserves_anchor_and_inserts_in_multi_block_file():
    units = [
        {"id": "h1", "kind": "header", "text": "A", "block_id": 1},
        {"id": "a1", "kind": "list_item", "text": "A1", "block_id": 10},
        {"id": "a2", "kind": "list_item", "text": "A2", "block_id": 10},
        {"id": "h2", "kind": "header", "text": "B", "block_id": 2},
        {"id": "b1", "kind": "list_item", "text": "B1", "block_id": 20},
    ]
    changes = [
        {
            "id": "execution:a:c1",
            "action": "add_after",
            "unit_id": "a2",
            "new_text": "New line",
            "new_unit": {
                "id": "new:execution:a:c1",
                "kind": "list_item",
                "text": "New line",
                "block_id": 10,
            },
        },
        {
            "id": "execution:a:c2",
            "action": "replace",
            "unit_id": "b1",
            "new_text": "B1 revised",
        },
    ]
    merged = merge_document(
        units,
        changes,
        {"execution:a:c1": True},
    )
    texts = [unit["text"] for unit in merged if unit["kind"] == "list_item"]
    assert texts == ["A1", "A2", "New line", "B1"]
    assert [unit["text"] for unit in merged if unit["kind"] == "header"] == ["A", "B"]


def test_merge_add_after_only_does_not_apply_unapproved_replace():
    units = [
        {"id": "i1", "kind": "list_item", "text": "Keep me", "block_id": 5},
        {"id": "i2", "kind": "list_item", "text": "Also keep", "block_id": 5},
    ]
    changes = [
        {
            "id": "c1",
            "action": "add_after",
            "unit_id": "i1",
            "new_text": "Added",
            "new_unit": {
                "id": "new:c1",
                "kind": "list_item",
                "text": "Added",
                "block_id": 5,
            },
        },
        {
            "id": "c2",
            "action": "replace",
            "unit_id": "i2",
            "new_text": "Would replace",
        },
    ]
    merged = merge_document(units, changes, {"c1": True})
    assert [unit["text"] for unit in merged] == ["Keep me", "Added", "Also keep"]
