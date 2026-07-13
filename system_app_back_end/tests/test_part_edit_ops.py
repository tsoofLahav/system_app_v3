from services.part_edit_ops import sanitize_part_edit_ops, summarize_ops


def test_sanitize_part_edit_ops_keeps_valid_replace_and_add():
    units = [
        {"id": "h1", "kind": "header", "text": "API"},
        {"id": "i1", "kind": "list_item", "text": "Old"},
        {"id": "i2", "kind": "list_item", "text": "Keep"},
    ]
    ops = [
        {"op": "replace", "unit_id": "i1", "text": "Updated"},
        {"op": "add_after", "unit_id": "i2", "text": "New point"},
        {"op": "replace", "unit_id": "other", "text": "Skip"},
    ]
    cleaned = sanitize_part_edit_ops(ops, units, "API")
    assert cleaned == [
        {"op": "replace", "unit_id": "i1", "text": "Updated"},
        {
            "op": "add_after",
            "unit_id": "i2",
            "text": "New point",
            "kind": "list_item",
        },
    ]


def test_summarize_ops_counts_by_type():
    ops = [
        {"op": "replace", "unit_id": "i1", "text": "A"},
        {"op": "add_after", "unit_id": "i1", "text": "B"},
        {"op": "add_after", "unit_id": "i1", "text": "C"},
        {"op": "remove", "unit_id": "i2", "text": ""},
    ]
    assert summarize_ops(ops) == {"replace": 1, "add_after": 2, "remove": 1}
