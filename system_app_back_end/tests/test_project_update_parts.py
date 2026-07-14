"""Tests for project update change-set shape and merge behavior."""

from types import SimpleNamespace

from services.ai_smart_update.change_set_builder import build_chained_add_after_changes
from services.ai_smart_update.project_update import _new_part_to_documents
from services.diff_engine import build_document_change_set, merge_document
from services.file_anchor import parts_topic_id_for_file


def test_parts_topic_id_prefers_anchor():
    file = SimpleNamespace(topic_id=1, anchor_topic_id=42)

    assert parts_topic_id_for_file(file) == 42


def test_parts_topic_id_falls_back_to_file_topic():
    file = SimpleNamespace(topic_id=7, anchor_topic_id=None)

    assert parts_topic_id_for_file(file) == 7


def test_project_update_event_is_forced_to_file_moved():
    from services.automation_definitions import apply_definition_to_params

    params = apply_definition_to_params(
        {"version": 2, "event": "file_moved_to_additional"},
        "project_update",
        "project_update",
    )

    assert params["event"] == "file_moved"


def test_build_chained_add_after_changes_uses_anchor_and_chain():
    units, changes = build_chained_add_after_changes(
        key="plan",
        anchor_unit_id="anchor:plan",
        items=["First", "Second"],
        kind="list_item",
    )

    assert len(units) == 1
    assert units[0]["id"] == "anchor:plan"
    assert units[0]["text"] == ""

    assert len(changes) == 2
    assert changes[0]["unit_id"] == "anchor:plan"
    assert changes[0]["new_text"] == "First"
    assert changes[0]["new_unit"]["id"] == "new:plan:c1"
    assert changes[1]["unit_id"] == "new:plan:c1"
    assert changes[1]["new_text"] == "Second"
    assert changes[1]["new_unit"]["id"] == "new:plan:c2"


def test_new_part_to_documents_has_anchor_only_units():
    documents = _new_part_to_documents(
        "Auth",
        {
            "plan_items": ["Goal A", "Goal B"],
            "execution_items": ["Detail"],
            "task_items": ["Task 1"],
        },
    )

    plan = next(doc for doc in documents if doc["key"] == "plan")
    assert len(plan["units"]) == 1
    assert plan["units"][0]["id"] == "anchor:plan"
    assert plan["units"][0]["text"] == ""
    assert len(plan["changes"]) == 2
    assert plan["changes"][0]["unit_id"] == "anchor:plan"
    assert plan["changes"][1]["unit_id"] == "new:plan:c1"


def test_merge_document_applies_only_approved_chained_additions():
    units, changes = build_chained_add_after_changes(
        key="plan",
        anchor_unit_id="anchor:plan",
        items=["First", "Second", "Third"],
        kind="list_item",
    )

    merged = merge_document(
        units,
        changes,
        {
            "plan:c1": True,
            "plan:c2": False,
            "plan:c3": True,
        },
    )

    texts = [unit["text"] for unit in merged if unit.get("text")]
    assert texts == ["First", "Third"]


def test_merge_document_with_no_approvals_yields_empty_content():
    units, changes = build_chained_add_after_changes(
        key="plan",
        anchor_unit_id="anchor:plan",
        items=["Only"],
        kind="list_item",
    )

    merged = merge_document(units, changes, {})
    content_units = [u for u in merged if (u.get("text") or "").strip()]

    assert content_units == []


def test_existing_part_prompt_requires_minimal_ops():
    from services.ai_smart_update.project_update import EXISTING_PART_PROMPT

    assert "only" in EXISTING_PART_PROMPT.lower()
    assert "replace" in EXISTING_PART_PROMPT
    assert "add_after" in EXISTING_PART_PROMPT
    assert "remove" in EXISTING_PART_PROMPT
    assert "unchanged" in EXISTING_PART_PROMPT.lower()


def test_merge_document_orders_multiple_add_after_on_same_anchor():
    units = [{"id": "u1", "kind": "list_item", "text": "Existing"}]
    changes = [
        {
            "id": "plan:c1",
            "action": "add_after",
            "unit_id": "u1",
            "new_text": "First",
            "new_unit": {"id": "new:plan:c1", "kind": "list_item", "text": "First"},
        },
        {
            "id": "plan:c2",
            "action": "add_after",
            "unit_id": "u1",
            "new_text": "Second",
            "new_unit": {"id": "new:plan:c2", "kind": "list_item", "text": "Second"},
        },
    ]

    merged = merge_document(units, changes, {"plan:c1": True, "plan:c2": True})
    texts = [unit["text"] for unit in merged]

    assert texts == ["Existing", "First", "Second"]


def test_part_change_prefix_is_unique_per_new_part_name():
    from services.ai_smart_update.project_update import _part_change_prefix

    assert _part_change_prefix(None, "Auth", 0) != _part_change_prefix(None, "Billing", 1)
    assert _part_change_prefix(5, "Auth", 0) == "part:5"


def test_execution_items_split_overview_and_bullets():
    from services.ai_smart_update.project_update import (
        _execution_item_kinds,
        _new_part_to_documents,
    )

    ordered, kinds = _execution_item_kinds(
        [
            "Overview paragraph about vision metrics.",
            "Build tools",
            "Develop formula",
        ]
    )
    assert ordered[0].startswith("Overview")
    assert kinds == ["paragraph", "list_item", "list_item"]

    documents = _new_part_to_documents(
        "Part",
        {
            "plan_items": ["Goal"],
            "execution_items": ordered,
            "task_items": ["Task"],
        },
    )
    execution = next(doc for doc in documents if doc["key"] == "execution")
    assert execution["units"][0]["kind"] == "paragraph"
    assert execution["changes"][0]["new_unit"]["kind"] == "paragraph"
    assert execution["changes"][1]["new_unit"]["kind"] == "list_item"


def test_execution_merge_produces_text_and_single_list():
    from services.ai_smart_update.project_update import _new_part_to_documents
    from services.unit_mapper import content_units_from_merged

    documents = _new_part_to_documents(
        "Part",
        {
            "execution_items": [
                "Overview paragraph about vision metrics.",
                "Build tools",
                "Develop formula",
            ],
        },
    )
    execution = next(doc for doc in documents if doc["key"] == "execution")
    decisions = {change["id"]: True for change in execution["changes"]}
    merged = merge_document(execution["units"], execution["changes"], decisions)
    units = content_units_from_merged(merged)

    assert units[0]["kind"] == "paragraph"
    assert [unit["text"] for unit in units if unit["kind"] == "list_item"] == [
        "Build tools",
        "Develop formula",
    ]


def test_prefixed_new_part_changes_merge_independently():
    from services.ai_smart_update.project_update import (
        _new_part_to_documents,
        _part_change_prefix,
        _prefix_changes,
    )

    docs_a = _prefix_changes(
        _new_part_to_documents("Part A", {"plan_items": ["A1"]}),
        _part_change_prefix(None, "Part A", 0),
    )
    docs_b = _prefix_changes(
        _new_part_to_documents("Part B", {"plan_items": ["B1"]}),
        _part_change_prefix(None, "Part B", 1),
    )
    plan_a = next(doc for doc in docs_a if doc["key"] == "plan")
    plan_b = next(doc for doc in docs_b if doc["key"] == "plan")

    assert plan_a["changes"][0]["id"] != plan_b["changes"][0]["id"]

    decisions = {
        plan_a["changes"][0]["id"]: True,
        plan_b["changes"][0]["id"]: True,
    }
    merged_a = merge_document(plan_a["units"], plan_a["changes"], decisions)
    merged_b = merge_document(plan_b["units"], plan_b["changes"], decisions)

    assert [u["text"] for u in merged_a if u.get("text")] == ["A1"]
    assert [u["text"] for u in merged_b if u.get("text")] == ["B1"]


def test_existing_part_add_after_op_produces_reviewable_change():
    units = [
        {"id": "u1", "kind": "list_item", "text": "Existing"},
        {"id": "u2", "kind": "list_item", "text": "Another"},
    ]
    doc = build_document_change_set(
        "plan",
        "Plan",
        units,
        [{"op": "add_after", "unit_id": "u1", "text": "New point"}],
    )

    assert len(doc["changes"]) == 1
    change = doc["changes"][0]
    assert change["action"] == "add_after"
    assert change["unit_id"] == "u1"
    assert change["new_text"] == "New point"
    assert change["new_unit"]["id"] == "new:plan:c1"
