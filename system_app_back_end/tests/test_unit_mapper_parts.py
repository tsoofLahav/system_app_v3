"""Tests for part-aware unit flattening and project update helpers."""

from types import SimpleNamespace

from services.ai_project_update_actions import (
    _normalize_doc_ops,
    _plan_has_new_part_ops,
    build_project_update_change_set,
)
from services.unit_mapper import (
    extract_part_names,
    flatten_file_by_parts_for_ai,
    summarize_parts_for_mapping,
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


def test_summarize_parts_for_mapping():
    units = [
        {"id": "h1", "kind": "header", "text": "API"},
        {"id": "i1", "kind": "list_item", "text": "Define contracts"},
        {"id": "i2", "kind": "list_item", "text": "Auth model"},
    ]
    summary = summarize_parts_for_mapping(units)
    assert "PART: API" in summary
    assert "Define contracts" in summary


def test_normalize_doc_ops_append_only():
    ops = [
        {"date": "2026-07-07", "text": "Shipped milestone"},
        {"op": "replace", "unit_id": "table:1:row:0", "text": "bad"},
        {"date": "", "text": "skip"},
    ]
    assert _normalize_doc_ops(ops) == [
        {"date": "2026-07-07", "text": "Shipped milestone"}
    ]


def test_plan_has_new_part_ops_detects_header_add_after():
    mapping = {"new_parts": ["Billing"]}
    plan_result = {
        "new_parts": [],
        "plan_ops": [
            {
                "op": "add_after",
                "unit_id": "block:1:item:0",
                "text": "Billing",
                "kind": "header",
            }
        ],
    }
    assert _plan_has_new_part_ops(plan_result, mapping)


def test_plan_has_new_part_ops_false_when_mapping_requires_new_but_missing():
    mapping = {"new_parts": ["Billing"]}
    plan_result = {"new_parts": [], "plan_ops": []}
    assert not _plan_has_new_part_ops(plan_result, mapping)


def test_build_project_update_change_set_includes_only_non_empty_documents(monkeypatch):
    plan = SimpleNamespace(id=1, name="Plan", type="plan")
    execution = SimpleNamespace(id=2, name="Execution", type="execution")
    tasks = SimpleNamespace(id=3, name="Tasks", type="tasks")
    doc = SimpleNamespace(id=4, name="Documentation", type="doc")

    monkeypatch.setattr(
        "services.ai_project_update_actions.units_from_file",
        lambda _file_id: [
            {
                "id": "block:9:item:0",
                "kind": "list_item",
                "text": "Existing point",
            }
        ],
    )
    monkeypatch.setattr(
        "services.ai_project_update_actions.units_from_doc_table",
        lambda _doc_file: [],
    )

    change_set = build_project_update_change_set(
        plan,
        execution,
        tasks,
        doc,
        {
            "execution_ops": [
                {
                    "op": "add_after",
                    "unit_id": "block:9:item:0",
                    "text": "Finalize API contract",
                }
            ],
            "doc_ops": [{"date": "2026-07-06", "text": "Reviewed API draft"}],
        },
    )

    keys = [document["key"] for document in change_set["documents"]]
    assert keys == ["execution", "doc"]
    execution_doc = change_set["documents"][0]
    assert execution_doc["changes"][0]["new_text"] == "Finalize API contract"
