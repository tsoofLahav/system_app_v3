"""Tests for patch_file / move_text / rewrite_file helpers."""

from unittest.mock import MagicMock, patch

from areas.files.services.document_v3 import serialize_document
from areas.production_agent.services.write_tools import (
    apply_document_text,
    insert_agent_text,
    move_text,
    resolve_write_mode,
)


def test_resolve_write_mode_review_ceiling():
    assert resolve_write_mode("move_text", "review") == "review"
    assert resolve_write_mode("patch_file", "review") == "review"


def test_resolve_write_mode_tool_defaults_under_direct():
    assert resolve_write_mode("patch_file", "direct_apply") == "review"
    assert resolve_write_mode("move_text", "direct_apply") == "direct_apply"
    assert resolve_write_mode("rewrite_file", "direct_apply") == "direct_apply"


def test_insert_agent_text_end_and_after_line():
    current = "Line one\nLine two\n"
    at_end, err = insert_agent_text(current, "New bit", anchor_type="end")
    assert err is None
    assert at_end.endswith("New bit\n")
    assert "Line two" in at_end

    mid, err = insert_agent_text(
        current, "Inserted", anchor_type="after_line", line=1
    )
    assert err is None
    assert mid.splitlines()[:3] == ["Line one", "Inserted", "Line two"]


def test_insert_agent_text_after_text():
    current = "[TABLE]\nA\tB\n[/TABLE]\n"
    new, err = insert_agent_text(
        current,
        "## Note\nHello",
        anchor_type="after_text",
        text="[/TABLE]",
    )
    assert err is None
    assert "[/TABLE]" in new
    assert "## Note" in new
    assert new.index("[/TABLE]") < new.index("## Note")


@patch("areas.production_agent.services.write_tools.apply_object_updates", return_value=[])
@patch("areas.production_agent.services.write_tools.save_file_version")
@patch("areas.production_agent.services.write_tools.db.session")
@patch("areas.production_agent.services.write_tools.ObjectEmbed")
def test_apply_document_text_direct(
    mock_embed_model,
    mock_session,
    mock_save_version,
    mock_apply_objects,
):
    file_row = MagicMock()
    file_row.id = 1
    file_row.topic_id = 1
    file_row.archived_at = None
    file_row.document_json = serialize_document({"version": 3, "blocks": []})
    mock_session.get.return_value = file_row
    mock_embed_model.query.filter_by.return_value.all.return_value = []

    result = apply_document_text(
        1,
        "## Title\n\nHello",
        scope={"file_ids": [1]},
        write_mode="direct_apply",
        tool_name="rewrite_file",
    )
    assert result.get("applied") is True
    assert result.get("tool") == "rewrite_file"
    mock_apply_objects.assert_called_once()


@patch("areas.production_agent.services.write_tools.apply_document_text")
@patch("areas.production_agent.services.write_tools._current_agent_text")
@patch("areas.production_agent.services.write_tools.db.session")
def test_move_text_uses_insert(
    mock_session, mock_current, mock_apply
):
    file_row = MagicMock()
    file_row.id = 12
    file_row.topic_id = 3
    file_row.archived_at = None
    mock_session.get.return_value = file_row
    mock_current.return_value = "Hello\n"
    mock_apply.return_value = {"applied": True, "tool": "move_text", "file_id": 12}

    result = move_text(
        12,
        "World",
        scope={"file_ids": [12]},
        write_mode="direct_apply",
        anchor_type="end",
    )
    assert result.get("applied") is True
    args, kwargs = mock_apply.call_args
    assert "World" in args[1]
    assert kwargs["tool_name"] == "move_text"
