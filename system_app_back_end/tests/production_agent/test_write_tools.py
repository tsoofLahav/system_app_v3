"""Tests for patch_file / move_text / rewrite_file helpers."""

from unittest.mock import MagicMock, patch

from areas.files.services.document_v3 import serialize_document
from areas.production_agent.services.write_tools import (
    apply_document_text,
    apply_replacements,
    insert_agent_text,
    move_text,
    patch_file,
    resolve_write_mode,
)


def test_resolve_write_mode_review_ceiling():
    assert resolve_write_mode("move_text", "review") == "review"
    assert resolve_write_mode("patch_file", "review") == "review"


def test_resolve_write_mode_direct_applies_all_tools():
    assert resolve_write_mode("patch_file", "direct_apply") == "direct_apply"
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


@patch("areas.production_agent.services.write_tools.purge_unreferenced_embeds_for_file")
@patch("areas.production_agent.services.write_tools.promote_legacy_embeds")
@patch("areas.production_agent.services.write_tools.apply_object_updates", return_value=[])
@patch("areas.production_agent.services.write_tools.save_file_version")
@patch("areas.production_agent.services.write_tools.db.session")
@patch("areas.production_agent.services.write_tools.ObjectEmbed")
def test_apply_document_text_direct(
    mock_embed_model,
    mock_session,
    mock_save_version,
    mock_apply_objects,
    mock_promote,
    mock_purge,
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
    assert "object_updates" in result
    mock_apply_objects.assert_called_once()
    mock_promote.assert_called()
    mock_purge.assert_called_once()

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


def test_apply_replacements_preserves_blank_lines():
    current = "Breakfast\n\nLunch: salad\n\nDinner\n"
    new, err = apply_replacements(
        current,
        [{"old_text": "Lunch: salad", "new_text": "Lunch: soup"}],
    )
    assert err is None
    assert new == "Breakfast\n\nLunch: soup\n\nDinner\n"


def test_apply_replacements_requires_unique_match():
    current = "x\nx\n"
    new, err = apply_replacements(
        current, [{"old_text": "x", "new_text": "y"}]
    )
    assert new is None
    assert "matched 2 times" in (err or "")


def test_apply_replacements_not_found():
    new, err = apply_replacements(
        "Hello\n", [{"old_text": "Missing", "new_text": "X"}]
    )
    assert new is None
    assert "not found" in (err or "")


@patch("areas.production_agent.services.write_tools.apply_document_text")
@patch("areas.production_agent.services.write_tools._current_agent_text")
@patch("areas.production_agent.services.write_tools.db.session")
def test_patch_file_uses_replacements(
    mock_session, mock_current, mock_apply
):
    file_row = MagicMock()
    file_row.id = 5
    file_row.topic_id = 1
    file_row.archived_at = None
    mock_session.get.return_value = file_row
    mock_current.return_value = "A\n\nB\n"
    mock_apply.return_value = {"applied": True, "tool": "patch_file", "file_id": 5}

    result = patch_file(
        5,
        [{"old_text": "B", "new_text": "C"}],
        scope={"file_ids": [5]},
        write_mode="direct_apply",
    )
    assert result.get("applied") is True
    assert result.get("replacements") == 1
    args, kwargs = mock_apply.call_args
    assert args[1] == "A\n\nC\n"
    assert kwargs["tool_name"] == "patch_file"
