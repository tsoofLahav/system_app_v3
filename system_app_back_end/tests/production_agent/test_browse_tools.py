"""Tests for production agent browse + create_object helpers."""

from unittest.mock import MagicMock, patch

from areas.files.services.document_marker_text import wrap_editor_text
from areas.production_agent.services.browse_tools import (
    block_index_after_agent_line,
    file_allowed,
)
from areas.production_agent.services.create_object_tool import create_object
from areas.production_agent.services.write_tools import resolve_write_mode


def test_file_allowed_workspace_and_legacy():
    file = MagicMock()
    file.id = 7
    file.topic_id = 3

    topic = MagicMock()
    topic.workspace_id = 1

    with patch(
        "areas.production_agent.services.browse_tools.db.session.get",
        return_value=topic,
    ):
        assert file_allowed(file, {"workspace_id": 1}) is True
        assert file_allowed(file, {"workspace_id": 9}) is False

    assert file_allowed(file, {"file_ids": [7]}) is True
    assert file_allowed(file, {"file_ids": [1]}) is False
    assert file_allowed(file, {"topic_ids": [3]}) is True


def test_block_index_after_agent_line_simple_paragraphs():
    doc = wrap_editor_text("One\n\nTwo\n\nThree")
    # after line 1 ("One") → insert before second block index 1
    assert block_index_after_agent_line(doc, {}, 1) == 1
    assert block_index_after_agent_line(doc, {}, 2) == 2
    assert block_index_after_agent_line(doc, {}, 99) is None
    assert block_index_after_agent_line(doc, {}, 0) == 0


def test_resolve_write_mode_includes_create_object():
    assert resolve_write_mode("create_object", "direct_apply") == "direct_apply"
    assert resolve_write_mode("create_object", "review") == "review"


@patch("areas.production_agent.services.create_object_tool.create_embed_in_file")
@patch("areas.production_agent.services.create_object_tool.load_objects_by_id", return_value={})
@patch("areas.production_agent.services.create_object_tool.db.session")
def test_create_object_direct(mock_session, _mock_load, mock_create):
    file_row = MagicMock()
    file_row.id = 12
    file_row.archived_at = None
    file_row.document_json = wrap_editor_text("Hello")
    mock_session.get.return_value = file_row

    embed = MagicMock()
    embed.id = 99
    mock_create.return_value = embed

    with patch(
        "areas.production_agent.services.create_object_tool.file_allowed",
        return_value=True,
    ):
        result = create_object(
            file_id=12,
            type_="task_list",
            scope={"workspace_id": 1},
            write_mode="direct_apply",
            title="Week",
            after_line=None,
        )

    assert result["applied"] is True
    assert result["object_id"] == 99
    assert result["file_id"] == 12
    mock_create.assert_called_once()
    kwargs = mock_create.call_args.kwargs
    assert kwargs["type_"] == "task_list"
    assert kwargs["title"] == "Week"
    assert kwargs["block_index"] is None


@patch("areas.production_agent.services.create_object_tool.create_embed_in_file")
@patch("areas.production_agent.services.create_object_tool.db.session")
def test_create_object_rejects_archived(mock_session, mock_create):
    file_row = MagicMock()
    file_row.id = 12
    file_row.archived_at = "yes"
    mock_session.get.return_value = file_row

    with patch(
        "areas.production_agent.services.create_object_tool.file_allowed",
        return_value=True,
    ):
        result = create_object(
            file_id=12,
            type_="info",
            scope={"workspace_id": 1},
            write_mode="direct_apply",
        )

    assert "error" in result
    mock_create.assert_not_called()
