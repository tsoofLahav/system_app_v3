"""Tests for production agent browse + create_object helpers."""

from unittest.mock import MagicMock, patch

from areas.files.services.document_marker_text import wrap_editor_text
from areas.production_agent.services.browse_tools import (
    block_index_after_agent_line,
    file_allowed,
    find_file,
    list_entities,
)
from areas.production_agent.services.create_object_tool import create_object
from areas.production_agent.services.write_tools import resolve_write_mode

BROWSE = "areas.production_agent.services.browse_tools"


def _topic(topic_id: int, name: str, *, archived: bool = False) -> MagicMock:
    topic = MagicMock()
    topic.id = topic_id
    topic.name = name
    topic.archived_at = "yes" if archived else None
    return topic


def _file(file_id: int, name: str, topic_id: int, *, archived: bool = False) -> MagicMock:
    file = MagicMock()
    file.id = file_id
    file.name = name
    file.topic_id = topic_id
    file.archived_at = "yes" if archived else None
    return file


def _files_query(rows):
    query = MagicMock()
    query.all.return_value = rows
    return MagicMock(return_value=query)


# Vision / nutrition / fitness: the agent must be able to tell them apart.
TOPICS = [_topic(1, "vision"), _topic(2, "nutrition"), _topic(3, "fitness")]
FILES = [_file(7, "daily log", 2), _file(12, "week plan", 3)]


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


def test_list_files_grouped_under_topic_names():
    with patch(f"{BROWSE}._topic_rows", return_value=TOPICS), patch(
        f"{BROWSE}._workspace_files_query", _files_query(FILES)
    ):
        result = list_entities(1, kind="files")

    assert result["grouped_by"] == "topic"
    assert [(g["topic_id"], g["topic"]) for g in result["topics"]] == [
        (1, "vision"),
        (2, "nutrition"),
        (3, "fitness"),
    ]
    by_name = {g["topic"]: g["files"] for g in result["topics"]}
    assert by_name["vision"] == []
    assert by_name["nutrition"] == [{"id": 7, "name": "daily log", "archived": False}]
    assert by_name["fitness"][0]["name"] == "week plan"


def test_list_files_skips_empty_archived_topic():
    topics = TOPICS + [_topic(4, "old", archived=True)]
    with patch(f"{BROWSE}._topic_rows", return_value=topics), patch(
        f"{BROWSE}._workspace_files_query", _files_query(FILES)
    ):
        result = list_entities(1, kind="files")

    assert "old" not in {g["topic"] for g in result["topics"]}


def test_list_objects_grouped_by_topic_then_file():
    embed = MagicMock()
    embed.id = 42
    embed.file_id = 12
    embed.type = "table"
    embed.payload = {}

    embed_query = MagicMock()
    embed_query.filter.return_value.order_by.return_value.all.return_value = [embed]

    with patch(f"{BROWSE}._topic_rows", return_value=TOPICS), patch(
        f"{BROWSE}._workspace_files_query", _files_query(FILES)
    ), patch(f"{BROWSE}.ObjectEmbed") as mock_embed_model:
        mock_embed_model.query = embed_query
        result = list_entities(1, kind="objects")

    # Only the topic and file that actually hold an object.
    assert len(result["topics"]) == 1
    group = result["topics"][0]
    assert group["topic"] == "fitness"
    assert group["files"] == [
        {
            "file_id": 12,
            "file": "week plan",
            "objects": [{"id": 42, "type": "table", "name": "Table"}],
        }
    ]


def test_find_file_hit_carries_topic_name():
    with patch(f"{BROWSE}._topic_rows", return_value=TOPICS), patch(
        f"{BROWSE}._workspace_files_query", _files_query(FILES)
    ):
        result = find_file(1, name="log")

    assert result["items"] == [
        {
            "id": 7,
            "name": "daily log",
            "topic_id": 2,
            "topic": "nutrition",
            "archived": False,
        }
    ]


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
