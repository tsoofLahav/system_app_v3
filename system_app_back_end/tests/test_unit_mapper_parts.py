"""Tests for part-aware unit flattening and project update helpers."""

from types import SimpleNamespace

from services.ai_project_update_actions import (
    _normalize_doc_ops,
    build_project_update_change_set,
    build_review_parts,
    input_log_has_part_headers,
)
from services.unit_mapper import (
    attach_mapped_log_content,
    build_part_removal_ops,
    extract_log_sections,
    extract_part_names,
    flatten_file_by_parts_for_ai,
    flatten_log_content,
    format_numbered_plan_headers,
    list_log_sections_for_map,
    list_plan_headers,
    match_plan_header_exact,
    normalize_content_payload,
    parse_header_map_instructions,
    part_change_id_prefix,
    resolve_plan_index,
    resolve_plan_part_name,
    slice_units_by_part,
    summarize_parts_for_mapping,
    synthesize_create_preview_from_content,
)
from services.part_diff import build_create_part_ops as create_ops


def test_extract_part_names_from_headers():
    units = [
        {"id": "h1", "kind": "header", "text": "Backend"},
        {"id": "p1", "kind": "paragraph", "text": "Intro"},
        {"id": "h2", "kind": "header", "text": "Frontend"},
    ]
    assert extract_part_names(units) == ["Backend", "Frontend"]


def test_list_plan_headers_and_log_sections_for_map():
    plan_units = [{"id": "h1", "kind": "header", "text": "API"}]
    log_sections = extract_log_sections(
        [
            {"id": "lh1", "kind": "header", "text": "API work"},
            {"id": "p1", "kind": "paragraph", "text": "Did things"},
        ]
    )
    assert list_plan_headers(plan_units) == ["API"]
    assert list_log_sections_for_map(log_sections) == "[0] API work"


def test_format_numbered_plan_headers():
    plan_units = [
        {"id": "h1", "kind": "header", "text": "API"},
        {"id": "h2", "kind": "header", "text": "Mobile"},
    ]
    formatted = format_numbered_plan_headers(plan_units)
    assert "[1] API" in formatted
    assert "[2] Mobile" in formatted


def test_parse_header_map_instructions_sparse_mapping():
    plan_units = [
        {"id": "h1", "kind": "header", "text": "X"},
        {"id": "h2", "kind": "header", "text": "Y"},
        {"id": "h3", "kind": "header", "text": "Z"},
    ]
    sections = extract_log_sections(
        [
            {"id": "h1", "kind": "header", "text": "A"},
            {"id": "p1", "kind": "paragraph", "text": "new area notes"},
            {"id": "h2", "kind": "header", "text": "B"},
            {"id": "p2", "kind": "paragraph", "text": "maps to Z"},
            {"id": "h3", "kind": "header", "text": "C"},
            {"id": "p3", "kind": "paragraph", "text": "retire X"},
        ]
    )
    result = parse_header_map_instructions(
        {
            "instructions": [
                {"action": "remove", "plan_index": 1},
                {"action": "update", "plan_index": 3, "log_section_index": 1},
                {"action": "create", "log_section_index": 0, "part_name": "A"},
            ]
        },
        plan_units,
        sections,
    )
    assert result["parts_to_remove"] == ["X"]
    assert len(result["parts"]) == 2
    create_part = next(item for item in result["parts"] if item["action"] == "create")
    update_part = next(item for item in result["parts"] if item["action"] == "update")
    assert create_part["part_name"] == "A"
    assert update_part["part_name"] == "Z"
    assert update_part["log_header"] == "B"


def test_resolve_plan_index():
    plan_units = [{"id": "h1", "kind": "header", "text": "API Integration"}]
    assert resolve_plan_index(plan_units, 1) == "API Integration"
    assert resolve_plan_index(plan_units, 9) == ""


def test_attach_mapped_log_content_uses_index():
    sections = extract_log_sections(
        [
            {"id": "h1", "kind": "header", "text": "Billing"},
            {"id": "p1", "kind": "paragraph", "text": "Started billing work"},
        ]
    )
    entry = attach_mapped_log_content(
        {"log_section_index": 0, "part_name": "Billing", "action": "create"},
        sections,
    )
    assert entry["log_header"] == "Billing"
    assert "billing work" in entry["log_content"]


def test_build_review_parts_create_uses_preview_units():
    units = [
        {"id": "h1", "kind": "header", "text": "API"},
        {"id": "p1", "kind": "paragraph", "text": "Worked on API"},
        {"id": "h2", "kind": "header", "text": "Mobile"},
        {"id": "p2", "kind": "paragraph", "text": "Shell progress"},
    ]
    sections = extract_log_sections(units)
    assert len(sections) == 2
    assert sections[0]["header"] == "API"
    assert flatten_log_content(sections[0]) == "Worked on API"


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


def test_build_review_parts_scopes_change_ids_per_part():
    plan_units = [
        {"id": "h1", "kind": "header", "text": "API"},
        {"id": "i1", "kind": "list_item", "text": "Old"},
        {"id": "h2", "kind": "header", "text": "Mobile"},
        {"id": "i2", "kind": "list_item", "text": "Shell"},
    ]
    per_part = [
        {
            "part_name": "API",
            "log_header": "API",
            "action": "update",
            "plan_ops": [{"op": "replace", "unit_id": "i1", "text": "Updated API"}],
            "execution_ops": [],
            "tasks_ops": [],
        },
        {
            "part_name": "Mobile",
            "log_header": "Mobile",
            "action": "update",
            "plan_ops": [
                {"op": "add_after", "unit_id": "i2", "text": "New mobile line", "kind": "list_item"}
            ],
            "execution_ops": [],
            "tasks_ops": [],
        },
    ]
    review = build_review_parts(
        per_part, plan_units, plan_units, plan_units, "Plan", "Execution", "Tasks"
    )
    api_id = review[0]["plan"]["changes"][0]["id"]
    mobile_id = review[1]["plan"]["changes"][0]["id"]
    assert api_id != mobile_id
    assert api_id.startswith("plan:api:")
    assert mobile_id.startswith("plan:mobile:")


def test_build_review_parts_create_includes_scoped_changes():
    plan_units = [{"id": "a1", "kind": "list_item", "text": "Existing"}]
    ops = create_ops(plan_units, "Billing", ["Essence"], "plan")
    per_part = [
        {
            "part_name": "Billing",
            "log_header": "Billing",
            "action": "create",
            "plan_ops": ops,
            "execution_ops": [],
            "tasks_ops": [],
        }
    ]
    review = build_review_parts(
        per_part, plan_units, plan_units, plan_units, "Plan", "Execution", "Tasks"
    )
    changes = review[0]["plan"]["changes"]
    assert len(changes) == 2
    assert changes[1]["action"] == "add_after"
    assert review[0]["plan"]["review_bundle"] is False


def test_build_review_parts_create_uses_synthetic_units():
    plan_units = [{"id": "a1", "kind": "list_item", "text": "Existing"}]
    ops = create_ops(plan_units, "Billing", ["Essence"], "plan")
    per_part = [
        {
            "part_name": "Billing",
            "log_header": "Billing",
            "action": "create",
            "content": {"plan": ["Essence"], "execution": [], "tasks": []},
            "plan_ops": ops,
            "execution_ops": [],
            "tasks_ops": [],
        }
    ]
    review = build_review_parts(
        per_part, plan_units, plan_units, plan_units, "Plan", "Execution", "Tasks"
    )
    assert review[0]["plan"]["units"][0]["id"] == "a1"
    assert review[0]["plan"]["changes"][0]["action"] == "add_after"
    assert review[0]["plan"]["review_bundle"] is False


def test_build_review_parts_remove_bundles_sections():
    plan_units = [
        {"id": "h1", "kind": "header", "text": "API"},
        {"id": "i1", "kind": "list_item", "text": "Point"},
    ]
    ops = build_part_removal_ops(plan_units, "API")
    per_part = [
        {
            "part_name": "API",
            "log_header": "API",
            "action": "remove",
            "plan_ops": ops,
            "execution_ops": ops,
            "tasks_ops": [],
        }
    ]
    review = build_review_parts(
        per_part, plan_units, plan_units, plan_units, "Plan", "Execution", "Tasks"
    )
    assert review[0]["action"] == "remove"
    assert review[0]["plan"]["review_bundle"] is True
    assert review[0]["plan"]["units"][0]["text"] == "Point"


def test_synthesize_create_preview_from_content():
    units = synthesize_create_preview_from_content("API", ["Point"], "plan")
    assert units[0]["text"] == "Point"


def test_normalize_content_payload():
    assert normalize_content_payload(
        {"plan": [" a "], "execution": "bad", "tasks": []}
    ) == {"plan": ["a"], "execution": [], "tasks": []}


def test_part_change_id_prefix_scopes_by_part():
    assert part_change_id_prefix("plan", "API Work") == "plan:apiwork"
    plan_units = [{"id": "h1", "kind": "header", "text": "API Integration"}]
    assert resolve_plan_part_name(plan_units, "api integration") == "API Integration"


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


def test_resolve_plan_part_name():
    plan_units = [{"id": "h1", "kind": "header", "text": "API Integration"}]
    assert match_plan_header_exact(plan_units, "api integration") == "API Integration"
    assert match_plan_header_exact(plan_units, "API") == ""


def test_build_project_update_change_set_excludes_doc(monkeypatch):
    plan = SimpleNamespace(id=1, name="Plan", type="plan")
    execution = SimpleNamespace(id=2, name="Execution", type="execution")
    tasks = SimpleNamespace(id=3, name="Tasks", type="tasks")

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
        [
            {
                "part_name": "API",
                "action": "update",
                "execution_ops": [
                    {
                        "op": "add_after",
                        "unit_id": "block:9:item:0",
                        "text": "Finalize API contract",
                    }
                ],
            }
        ],
    )

    keys = [document["key"] for document in change_set["documents"]]
    assert keys == ["execution"]


def test_review_parts_and_change_set_share_change_ids(monkeypatch):
    plan = SimpleNamespace(id=1, name="Plan", type="plan")
    execution = SimpleNamespace(id=2, name="Execution", type="execution")
    tasks = SimpleNamespace(id=3, name="Tasks", type="tasks")
    plan_units = [
        {"id": "h1", "kind": "header", "text": "API"},
        {"id": "i1", "kind": "list_item", "text": "Old line"},
        {"id": "i2", "kind": "list_item", "text": "Anchor"},
    ]
    monkeypatch.setattr(
        "services.ai_project_update_actions.units_from_file",
        lambda _file_id: plan_units,
    )
    per_part = [
        {
            "part_name": "API",
            "log_header": "API",
            "action": "update",
            "plan_ops": [
                {"op": "replace", "unit_id": "i1", "text": "Revised line"},
                {
                    "op": "add_after",
                    "unit_id": "i2",
                    "text": "Brand new",
                    "kind": "list_item",
                },
            ],
            "execution_ops": [],
            "tasks_ops": [],
        }
    ]

    review = build_review_parts(
        per_part, plan_units, plan_units, plan_units, "Plan", "Execution", "Tasks"
    )
    change_set = build_project_update_change_set(plan, execution, tasks, per_part)

    review_changes = review[0]["plan"]["changes"]
    finalize_changes = next(
        doc["changes"] for doc in change_set["documents"] if doc["key"] == "plan"
    )
    assert [change["id"] for change in review_changes] == [
        change["id"] for change in finalize_changes
    ]
    assert [change["action"] for change in review_changes] == [
        change["action"] for change in finalize_changes
    ]
