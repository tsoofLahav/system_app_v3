"""Tests for part-aware unit flattening and project update helpers."""

from types import SimpleNamespace

from services.ai_project_update_actions import (
    _normalize_doc_ops,
    build_project_update_change_set,
    build_review_parts,
    input_log_has_part_headers,
)
from services.unit_mapper import (
    build_part_removal_ops,
    extract_log_sections,
    extract_part_names,
    flatten_file_by_parts_for_ai,
    slice_units_by_part,
    summarize_parts_for_mapping,
)


def test_extract_part_names_from_headers():
    units = [
        {"id": "h1", "kind": "header", "text": "Backend"},
        {"id": "p1", "kind": "paragraph", "text": "Intro"},
        {"id": "h2", "kind": "header", "text": "Frontend"},
    ]
    assert extract_part_names(units) == ["Backend", "Frontend"]


def test_extract_log_sections_splits_by_header():
    units = [
        {"id": "h1", "kind": "header", "text": "API"},
        {"id": "p1", "kind": "paragraph", "text": "Worked on API"},
        {"id": "h2", "kind": "header", "text": "Mobile"},
        {"id": "p2", "kind": "paragraph", "text": "Shell progress"},
    ]
    sections = extract_log_sections(units)
    assert len(sections) == 2
    assert sections[0]["header"] == "API"
    assert sections[1]["header"] == "Mobile"


def test_slice_units_by_part():
    units = [
        {"id": "h1", "kind": "header", "text": "API"},
        {"id": "i1", "kind": "list_item", "text": "Point"},
        {"id": "h2", "kind": "header", "text": "Mobile"},
        {"id": "i2", "kind": "list_item", "text": "Other"},
    ]
    api_slice = slice_units_by_part(units, "API")
    assert [unit["id"] for unit in api_slice] == ["h1", "i1"]


def test_build_part_removal_ops():
    units = [
        {"id": "h1", "kind": "header", "text": "API"},
        {"id": "i1", "kind": "list_item", "text": "Point"},
    ]
    ops = build_part_removal_ops(units, "API")
    assert len(ops) == 2
    assert ops[0]["op"] == "remove"


def test_input_log_has_part_headers(monkeypatch):
    monkeypatch.setattr(
        "services.ai_project_update_actions.units_from_file",
        lambda _file_id: [{"id": "h1", "kind": "header", "text": "API"}],
    )
    assert input_log_has_part_headers(SimpleNamespace(id=1))


def test_build_review_parts_groups_by_part():
    plan_units = [
        {"id": "h1", "kind": "header", "text": "API"},
        {"id": "i1", "kind": "list_item", "text": "Old"},
    ]
    per_part = [
        {
            "target_part": "API",
            "log_header": "API work",
            "action": "update",
            "plan_ops": [
                {
                    "op": "replace",
                    "unit_id": "i1",
                    "text": "Updated",
                }
            ],
            "execution_ops": [],
            "tasks_ops": [],
        }
    ]
    review = build_review_parts(
        per_part, plan_units, plan_units, plan_units, "Plan", "Execution", "Tasks"
    )
    assert len(review) == 1
    assert review[0]["part_name"] == "API"
    assert review[0]["plan"]["changes"][0]["new_text"] == "Updated"


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


def test_normalize_doc_ops_append_only():
    ops = [
        {"date": "2026-07-07", "text": "Shipped milestone"},
        {"op": "replace", "unit_id": "table:1:row:0", "text": "bad"},
        {"date": "", "text": "skip"},
    ]
    assert _normalize_doc_ops(ops) == [
        {"date": "2026-07-07", "text": "Shipped milestone"}
    ]


def test_build_project_update_change_set_excludes_doc(monkeypatch):
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

    change_set = build_project_update_change_set(
        plan,
        execution,
        tasks,
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
    assert keys == ["execution"]
