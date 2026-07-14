"""Parity tests for shared ai_smart_update helpers."""

from services.ai_smart_update.change_set_builder import (
    CHANGE_SET_VERSION_PART,
    build_part_change_set,
    build_process_change_set,
)
from services.ai_smart_update.unit_ops import normalize_ops


def test_normalize_ops_filters_invalid_entries():
    ops = normalize_ops(
        [
            {"op": "replace", "unit_id": "u1", "text": "hello"},
            {"op": "bad", "unit_id": "u2", "text": "skip"},
            {"op": "add_after", "unit_id": "", "text": "skip"},
            {"op": "remove", "unit_id": "u3"},
        ]
    )

    assert len(ops) == 2
    assert ops[0]["op"] == "replace"
    assert ops[1]["op"] == "remove"


def test_build_process_change_set_uses_version_one():
    payload = build_process_change_set(
        [{"key": "plan", "title": "Plan", "units": [], "changes": []}]
    )

    assert payload["version"] == 1
    assert len(payload["documents"]) == 1


def test_build_part_change_set_includes_log_and_doc_append():
    payload = build_part_change_set(
        log_file={"id": 9, "name": "Log", "date": "2026-07-14"},
        parts=[
            {
                "part_id": 3,
                "part_name": "Auth",
                "is_new": False,
                "documents": [],
            }
        ],
        doc_append={"rows": [{"date": "2026-07-14", "text": "Shipped auth"}]},
    )

    assert payload["version"] == CHANGE_SET_VERSION_PART
    assert payload["log_file"]["id"] == 9
    assert payload["parts"][0]["part_name"] == "Auth"
    assert payload["doc_append"]["rows"][0]["text"] == "Shipped auth"
