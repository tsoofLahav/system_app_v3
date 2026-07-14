"""Tests for project update change-set shape and merge behavior."""

from types import SimpleNamespace

from services.ai_smart_update.change_set_builder import (
    build_chained_add_after_changes,
    build_segment_change_set,
)
from services.ai_smart_update.document_segments import (
    execution_segments_from_ai,
    plan_segments_from_ai,
    segments_from_part_blocks,
    segments_to_units,
)
from services.ai_smart_update.project_update import _new_part_to_documents
from services.diff_engine import build_document_change_set, merge_document
from services.file_anchor import parts_topic_id_for_file
from services.unit_mapper import content_units_from_merged


def _block_kinds_from_units(units: list[dict]) -> list[str]:
    kinds = []
    for unit in units:
        kind = unit.get("kind")
        if kind in ("paragraph", "text", "summary"):
            if not kinds or kinds[-1] != "text":
                kinds.append("text")
        elif kind == "list_item":
            if not kinds or kinds[-1] != "list":
                kinds.append("list")
        elif kind == "task":
            if not kinds or kinds[-1] != "task":
                kinds.append("task")
    return kinds


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


def test_segments_from_part_blocks_use_one_paragraph_per_text_block():
    blocks = [
        SimpleNamespace(id=1, type="header", content={"text": "Part"}),
        SimpleNamespace(id=2, type="text", content={"text": "Intro paragraph."}),
        SimpleNamespace(
            id=3,
            type="list",
            content={"items": [{"text": "Point A"}, {"text": "Point B"}]},
        ),
        SimpleNamespace(id=4, type="text", content={"text": "Second paragraph."}),
    ]

    segments = segments_from_part_blocks(blocks)
    units = segments_to_units(segments)

    assert [segment["block_kind"] for segment in segments] == ["text", "list", "text"]
    assert units[0]["kind"] == "paragraph"
    assert units[0]["text"] == "Intro paragraph."
    assert [unit["text"] for unit in units if unit["kind"] == "list_item"] == [
        "Point A",
        "Point B",
    ]
    assert units[-1]["text"] == "Second paragraph."


def test_plan_segments_from_ai_supports_intro_and_points():
    segments = plan_segments_from_ai(
        {"intro": "Overview", "points": ["Goal A", "Goal B"]}
    )

    assert [segment["block_kind"] for segment in segments] == ["text", "list"]
    assert segments[0]["items"] == ["Overview"]
    assert segments[1]["items"] == ["Goal A", "Goal B"]


def test_execution_segments_from_ai_repeats_text_and_list_pairs():
    segments = execution_segments_from_ai(
        [
            {"text": "Elaboration 1", "subpoints": ["a", "b"]},
            {"text": "Elaboration 2", "subpoints": ["c"]},
        ]
    )

    assert [segment["block_kind"] for segment in segments] == [
        "text",
        "list",
        "text",
        "list",
    ]


def test_new_part_to_documents_builds_segment_aware_plan_and_execution():
    documents = _new_part_to_documents(
        "Auth",
        {
            "plan": {"intro": "Overview", "points": ["Goal A", "Goal B"]},
            "execution": [
                {"text": "Detail A", "subpoints": ["step 1", "step 2"]},
                {"text": "Detail B", "subpoints": ["step 3"]},
            ],
            "task_items": ["Task 1"],
        },
    )

    plan = next(doc for doc in documents if doc["key"] == "plan")
    execution = next(doc for doc in documents if doc["key"] == "execution")
    tasks = next(doc for doc in documents if doc["key"] == "tasks")

    assert plan["changes"][0]["new_unit"]["kind"] == "paragraph"
    assert plan["changes"][1]["new_unit"]["kind"] == "list_item"
    assert execution["changes"][0]["new_unit"]["kind"] == "paragraph"
    assert execution["changes"][1]["new_unit"]["kind"] == "list_item"
    assert execution["changes"][-1]["new_unit"]["kind"] == "list_item"
    assert execution["changes"][0]["new_unit"]["segment_id"] == "seg:execution:0"
    assert len(tasks["changes"]) == 1


def test_plan_round_trip_produces_text_then_list_blocks():
    documents = _new_part_to_documents(
        "Part",
        {"plan": {"intro": "Overview", "points": ["A", "B"]}},
    )
    plan = next(doc for doc in documents if doc["key"] == "plan")
    decisions = {change["id"]: True for change in plan["changes"]}
    merged = merge_document(plan["units"], plan["changes"], decisions)
    units = content_units_from_merged(merged)

    assert _block_kinds_from_units(units) == ["text", "list"]
    assert units[0]["text"] == "Overview"
    assert [unit["text"] for unit in units if unit["kind"] == "list_item"] == [
        "A",
        "B",
    ]


def test_execution_round_trip_produces_alternating_text_and_list_blocks():
    documents = _new_part_to_documents(
        "Part",
        {
            "execution": [
                {"text": "Elab 1", "subpoints": ["s1", "s2"]},
                {"text": "Elab 2", "subpoints": ["s3"]},
            ]
        },
    )
    execution = next(doc for doc in documents if doc["key"] == "execution")
    decisions = {change["id"]: True for change in execution["changes"]}
    merged = merge_document(execution["units"], execution["changes"], decisions)
    units = content_units_from_merged(merged)

    assert _block_kinds_from_units(units) == ["text", "list", "text", "list"]
    assert [unit["text"] for unit in units if unit["kind"] == "paragraph"] == [
        "Elab 1",
        "Elab 2",
    ]
    assert [unit["text"] for unit in units if unit["kind"] == "list_item"] == [
        "s1",
        "s2",
        "s3",
    ]


def test_build_segment_change_set_attaches_segment_ids():
    doc = build_segment_change_set(
        key="execution",
        title="Execution",
        segments=execution_segments_from_ai(
            [{"text": "One", "subpoints": ["a"]}]
        ),
    )

    assert doc["changes"][0]["new_unit"]["segment_id"] == "seg:execution:0"
    assert doc["changes"][1]["new_unit"]["segment_id"] == "seg:execution:1"


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


def test_prefixed_new_part_changes_merge_independently():
    from services.ai_smart_update.project_update import (
        _new_part_to_documents,
        _part_change_prefix,
        _prefix_changes,
    )

    docs_a = _prefix_changes(
        _new_part_to_documents("Part A", {"plan": {"points": ["A1"]}}),
        _part_change_prefix(None, "Part A", 0),
    )
    docs_b = _prefix_changes(
        _new_part_to_documents("Part B", {"plan": {"points": ["B1"]}}),
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
