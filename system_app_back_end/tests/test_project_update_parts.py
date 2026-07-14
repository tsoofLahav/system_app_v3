"""Tests for project update change-set shape and anchor helpers."""

from types import SimpleNamespace

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
