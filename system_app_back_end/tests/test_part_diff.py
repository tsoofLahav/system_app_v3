"""Tests for programmatic part diff helpers."""

from services.part_diff import (
    align_content_to_ops,
    build_create_part_ops,
    build_update_part_ops,
    sanitize_diff_ops,
)


def test_build_create_part_ops_adds_header_and_items():
    units = [{"id": "a1", "kind": "list_item", "text": "Existing"}]
    ops = build_create_part_ops(units, "Billing", ["Essence line"], "plan")

    assert len(ops) == 2
    assert ops[0]["kind"] == "header"
    assert ops[0]["text"] == "Billing"
    assert ops[0]["unit_id"] == "a1"
    assert ops[1]["text"] == "Essence line"


def test_build_create_part_ops_uses_task_kind_for_tasks_file():
    units = [{"id": "t0", "kind": "task", "text": "Old task"}]
    ops = build_create_part_ops(units, "API", ["Ship endpoint"], "tasks")

    assert ops[1]["kind"] == "task"


def test_build_update_part_ops_replaces_revised_line():
    units = [
        {"id": "h1", "kind": "header", "text": "API"},
        {"id": "i1", "kind": "list_item", "text": "Define contracts"},
        {"id": "i2", "kind": "list_item", "text": "Ship UI"},
    ]
    ops = build_update_part_ops(
        units,
        "API",
        ["Define API contracts", "Ship UI"],
        "plan",
    )

    assert len(ops) == 1
    assert ops[0]["op"] == "replace"
    assert ops[0]["unit_id"] == "i1"


def test_build_update_part_ops_adds_new_line_without_replacing_last():
    units = [
        {"id": "h1", "kind": "header", "text": "API"},
        {"id": "i1", "kind": "list_item", "text": "Define contracts"},
        {"id": "i2", "kind": "list_item", "text": "Ship UI"},
    ]
    ops = build_update_part_ops(
        units,
        "API",
        ["Define contracts", "Ship UI", "Add monitoring"],
        "plan",
    )

    assert len(ops) == 1
    assert ops[0]["op"] == "add_after"
    assert ops[0]["unit_id"] == "i2"
    assert ops[0]["text"] == "Add monitoring"


def test_align_content_to_ops_replaces_similar_line():
    units = [
        {"id": "h1", "kind": "header", "text": "API"},
        {"id": "i1", "kind": "list_item", "text": "Define contracts"},
    ]
    ops = align_content_to_ops(units, "API", ["Define API contracts"], "plan")

    assert len(ops) == 1
    assert ops[0]["op"] == "replace"
    assert ops[0]["unit_id"] == "i1"


def test_sanitize_diff_ops_falls_back_when_invalid_ids():
    units = [
        {"id": "h1", "kind": "header", "text": "API"},
        {"id": "i1", "kind": "list_item", "text": "Old item"},
    ]
    invalid = [{"op": "replace", "unit_id": "missing", "text": "New"}]
    ops = sanitize_diff_ops(invalid, units, "API", ["Old item revised"], "plan")

    assert len(ops) == 1
    assert ops[0]["op"] == "replace"
    assert ops[0]["unit_id"] == "i1"
