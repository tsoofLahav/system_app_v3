from services.diff_engine import merge_document


def test_merge_add_after_inserts_without_replacing_anchor():
    units = [
        {"id": "h1", "kind": "header", "text": "API"},
        {"id": "i1", "kind": "list_item", "text": "Keep"},
        {"id": "i2", "kind": "list_item", "text": "Anchor"},
    ]
    changes = [
        {
            "id": "plan:api:c1",
            "action": "add_after",
            "unit_id": "i2",
            "old_text": "",
            "new_text": "Brand new",
            "new_unit": {
                "id": "new:plan:api:c1",
                "kind": "list_item",
                "text": "Brand new",
            },
        }
    ]
    merged = merge_document(units, changes, {"plan:api:c1": True})
    assert [unit["text"] for unit in merged if unit["kind"] == "list_item"] == [
        "Keep",
        "Anchor",
        "Brand new",
    ]


def test_merge_replace_does_not_insert():
    units = [
        {"id": "h1", "kind": "header", "text": "API"},
        {"id": "i1", "kind": "list_item", "text": "Old line"},
        {"id": "i2", "kind": "list_item", "text": "Other"},
    ]
    changes = [
        {
            "id": "plan:api:c1",
            "action": "replace",
            "unit_id": "i1",
            "old_text": "Old line",
            "new_text": "Revised line",
        }
    ]
    merged = merge_document(units, changes, {"plan:api:c1": True})
    assert [unit["text"] for unit in merged if unit["kind"] == "list_item"] == [
        "Revised line",
        "Other",
    ]
