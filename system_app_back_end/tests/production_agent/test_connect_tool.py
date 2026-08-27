"""Tests for the production agent connect tool."""

from areas.production_agent.services.connect_tool import (
    _compose_info_text,
    _find_span,
    connect_tool,
)


def test_compose_info_text_matches_the_file_field():
    assert _compose_info_text("", "") == ""
    assert _compose_info_text("Title", "") == "Title"
    assert _compose_info_text("Title", "Body") == "Title\nBody"


def test_find_span_first_match():
    assert _find_span("please call the clinic today", "call the clinic") == (7, 22)
    assert _find_span("hello", "missing") is None


def test_connect_rejects_unknown_action():
    result = connect_tool(
        workspace_id=1,
        action="merge",
        write_mode="direct_apply",
    )
    assert result["error"].startswith("action must be")


def test_related_requires_source():
    result = connect_tool(
        workspace_id=1,
        action="related",
        write_mode="direct_apply",
        target_object_id=2,
    )
    assert "source_object_id" in result["error"]


def test_description_requires_a_host():
    result = connect_tool(
        workspace_id=1,
        action="description",
        write_mode="direct_apply",
        target_object_id=2,
        text="clinic",
    )
    assert "source_object_id or source_task_id" in result["error"]
