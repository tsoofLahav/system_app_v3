"""Tests for production agent browse + create_object helpers."""

from unittest.mock import MagicMock, patch

from areas.files.services.document_marker_text import wrap_editor_text
from areas.production_agent.services.browse_tools import (
    block_index_after_agent_line,
    file_allowed,
    find_file,
    list_archived_files,
    list_entities,
)
from areas.production_agent.services.create_object_tool import create_object
from areas.production_agent.services.write_tools import resolve_write_mode

BROWSE = "areas.production_agent.services.browse_tools"


def _topic(topic_id: int, name: str, *, archived: bool = False) -> MagicMock:
    topic = MagicMock()
    topic.id = topic_id
    topic.name = name
    topic.topic_type_id = None
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
    assert [(g["topic_id"], g["topic"], g["topic_type"]) for g in result["topics"]] == [
        (1, "vision", ""),
        (2, "nutrition", ""),
        (3, "fitness", ""),
    ]
    by_name = {g["topic"]: g["files"] for g in result["topics"]}
    assert by_name["vision"] == []
    assert by_name["nutrition"] == [{"id": 7, "name": "daily log", "archived": False}]
    assert by_name["fitness"][0]["name"] == "week plan"


def test_list_files_omits_archived_rows():
    rows = FILES + [_file(99, "old log", 2, archived=True)]
    with patch(f"{BROWSE}._topic_rows", return_value=TOPICS), patch(
        f"{BROWSE}._workspace_files_query", _files_query(rows)
    ):
        result = list_entities(1, kind="files")

    by_name = {g["topic"]: g["files"] for g in result["topics"]}
    assert [f["name"] for f in by_name["nutrition"]] == ["daily log"]


def test_list_files_queries_live_only():
    query = MagicMock()
    query.all.return_value = FILES
    with patch(f"{BROWSE}._topic_rows", return_value=TOPICS), patch(
        f"{BROWSE}._workspace_files_query", return_value=query
    ) as mock_files:
        list_entities(1, kind="files")
    mock_files.assert_called_once_with(1, topic_id=None, include_archived=False)


def test_list_archived_groups_archived_files():
    archived = [_file(99, "old log", 2, archived=True)]
    with patch(f"{BROWSE}._topic_rows", return_value=TOPICS), patch(
        f"{BROWSE}._workspace_files_query", _files_query(archived)
    ):
        result = list_archived_files(1)

    assert result["kind"] == "archived_files"
    assert [(g["topic"], [f["name"] for f in g["files"]]) for g in result["topics"]] == [
        ("nutrition", ["old log"]),
    ]
    assert result["topics"][0]["files"][0]["archived"] is True


def test_list_archived_filters_by_topic():
    archived = [
        _file(99, "old log", 2, archived=True),
        _file(100, "old plan", 3, archived=True),
    ]
    topic = MagicMock()
    topic.workspace_id = 1
    with patch(f"{BROWSE}._topic_rows", return_value=TOPICS), patch(
        f"{BROWSE}.db.session.get", return_value=topic
    ), patch(
        f"{BROWSE}._workspace_files_query", _files_query(archived)
    ) as mock_files:
        result = list_archived_files(1, topic_id=3)

    mock_files.assert_called_once_with(1, topic_id=3, archived_only=True)
    assert [g["topic"] for g in result["topics"]] == ["fitness"]
    assert result["topics"][0]["files"][0]["name"] == "old plan"


def test_list_archived_rejects_unknown_topic():
    with patch(f"{BROWSE}.db.session.get", return_value=None):
        result = list_archived_files(1, topic_id=99)
    assert result == {"error": "topic not found"}


def test_list_archived_skips_topics_with_no_archived_files():
    with patch(f"{BROWSE}._topic_rows", return_value=TOPICS), patch(
        f"{BROWSE}._workspace_files_query", _files_query([])
    ):
        result = list_archived_files(1)
    assert result["topics"] == []


def test_runner_wires_list_archived():
    from areas.production_agent.services.runner import TOOL_DEFS, _dispatch_tool
    import inspect

    assert any(t["name"] == "list_archived" for t in TOOL_DEFS)
    source = inspect.getsource(_dispatch_tool)
    assert 'name == "list_archived"' in source
    assert "list_archived_files" in source


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
            "topic_type": "",
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


@patch("areas.production_agent.services.create_object_tool.store_image_bytes")
@patch("areas.production_agent.services.create_object_tool.generate_image")
@patch("areas.production_agent.services.create_object_tool.create_embed_in_file")
@patch("areas.production_agent.services.create_object_tool.load_objects_by_id", return_value={})
@patch("areas.production_agent.services.create_object_tool.db.session")
def test_create_object_image_generates_and_stores(
    mock_session, _mock_load, mock_create, mock_generate, mock_store
):
    file_row = MagicMock()
    file_row.id = 12
    file_row.archived_at = None
    file_row.document_json = wrap_editor_text("Hello")
    mock_session.get.return_value = file_row

    embed = MagicMock()
    embed.id = 44
    mock_create.return_value = embed
    mock_generate.return_value = b"png-bytes"
    mock_store.return_value = "/images/generated_abc.png"

    with patch(
        "areas.production_agent.services.create_object_tool.file_allowed",
        return_value=True,
    ), patch(
        "areas.production_agent.services.create_object_tool._empty_image_embed",
        return_value=None,
    ):
        result = create_object(
            file_id=12,
            type_="image",
            scope={"workspace_id": 1},
            write_mode="direct_apply",
            title="Garden",
            body="watercolor vegetable garden",
        )

    assert result["applied"] is True
    assert result["object_id"] == 44
    assert result["url"] == "/images/generated_abc.png"
    mock_generate.assert_called_once_with("watercolor vegetable garden")
    mock_store.assert_called_once_with(b"png-bytes", original_name="generated.png")
    kwargs = mock_create.call_args.kwargs
    assert kwargs["payload"] == {
        "url": "/images/generated_abc.png",
        "caption": "Garden",
    }


@patch("areas.production_agent.services.create_object_tool.generate_image")
@patch("areas.production_agent.services.create_object_tool.create_embed_in_file")
@patch("areas.production_agent.services.create_object_tool.db.session")
def test_create_object_image_requires_a_description(
    mock_session, mock_create, mock_generate
):
    file_row = MagicMock()
    file_row.id = 12
    file_row.archived_at = None
    mock_session.get.return_value = file_row

    with patch(
        "areas.production_agent.services.create_object_tool.file_allowed",
        return_value=True,
    ):
        result = create_object(
            file_id=12,
            type_="image",
            scope={"workspace_id": 1},
            write_mode="direct_apply",
            title="",
            body="",
        )

    assert "error" in result
    mock_create.assert_not_called()
    mock_generate.assert_not_called()


@patch("areas.production_agent.services.create_object_tool.store_image_bytes")
@patch("areas.production_agent.services.create_object_tool.generate_image")
@patch("areas.production_agent.services.create_object_tool.create_embed_in_file")
@patch("areas.production_agent.services.create_object_tool.load_objects_by_id", return_value={})
@patch("areas.production_agent.services.create_object_tool.db.session")
def test_create_object_image_uses_title_when_body_empty(
    mock_session, _mock_load, mock_create, mock_generate, mock_store
):
    file_row = MagicMock()
    file_row.id = 12
    file_row.archived_at = None
    file_row.document_json = wrap_editor_text("Hello")
    mock_session.get.return_value = file_row
    embed = MagicMock()
    embed.id = 45
    mock_create.return_value = embed
    mock_generate.return_value = b"png"
    mock_store.return_value = "/images/x.png"

    with patch(
        "areas.production_agent.services.create_object_tool.file_allowed",
        return_value=True,
    ), patch(
        "areas.production_agent.services.create_object_tool._empty_image_embed",
        return_value=None,
    ):
        create_object(
            file_id=12,
            type_="image",
            scope={"workspace_id": 1},
            write_mode="direct_apply",
            title="a red bicycle",
            body="",
        )

    mock_generate.assert_called_once_with("a red bicycle")


@patch("areas.production_agent.services.create_object_tool.store_image_bytes")
@patch("areas.production_agent.services.create_object_tool.generate_image")
@patch("areas.production_agent.services.create_object_tool.create_embed_in_file")
@patch("areas.production_agent.services.create_object_tool.db.session")
def test_create_object_image_fills_empty_slot(
    mock_session, mock_create, mock_generate, mock_store
):
    file_row = MagicMock()
    file_row.id = 12
    file_row.archived_at = None
    mock_session.get.return_value = file_row
    existing = MagicMock()
    existing.id = 7
    existing.payload = {}
    mock_generate.return_value = b"png"
    mock_store.return_value = "/images/filled.png"

    with patch(
        "areas.production_agent.services.create_object_tool.file_allowed",
        return_value=True,
    ), patch(
        "areas.production_agent.services.create_object_tool._empty_image_embed",
        return_value=existing,
    ):
        result = create_object(
            file_id=12,
            type_="image",
            scope={"workspace_id": 1},
            write_mode="direct_apply",
            title="",
            body="a lighthouse at dusk",
        )

    assert result["object_id"] == 7
    assert result["filled_existing"] is True
    assert existing.payload["url"] == "/images/filled.png"
    mock_create.assert_not_called()


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


@patch("areas.production_agent.services.create_file_tool.file_ops.create_file")
@patch("areas.production_agent.services.create_file_tool.db.session")
def test_create_file_direct(mock_session, mock_create):
    from areas.production_agent.services.create_file_tool import (
        create_file as create_file_tool,
    )

    topic = MagicMock()
    topic.id = 3
    topic.name = "fitness"
    topic.workspace_id = 1
    topic.archived_at = None
    mock_session.get.return_value = topic

    file_row = MagicMock()
    file_row.id = 88
    file_row.name = "week plan"
    mock_create.return_value = file_row

    result = create_file_tool(
        topic_id=3,
        name="week plan",
        scope={"workspace_id": 1},
        write_mode="direct_apply",
    )

    assert result["applied"] is True
    assert result["file_id"] == 88
    assert result["topic"] == "fitness"
    mock_create.assert_called_once()
    assert mock_create.call_args.kwargs["place_first"] is True


@patch("areas.production_agent.services.create_file_tool.file_ops.create_file")
@patch("areas.production_agent.services.create_file_tool.db.session")
def test_create_file_rejects_other_workspace(mock_session, mock_create):
    from areas.production_agent.services.create_file_tool import (
        create_file as create_file_tool,
    )

    topic = MagicMock()
    topic.id = 3
    topic.workspace_id = 9
    topic.archived_at = None
    mock_session.get.return_value = topic

    result = create_file_tool(
        topic_id=3,
        name="week plan",
        scope={"workspace_id": 1},
        write_mode="direct_apply",
    )

    assert result["error"] == "topic out of scope"
    mock_create.assert_not_called()


def test_resolve_write_mode_includes_create_file():
    assert resolve_write_mode("create_file", "direct_apply") == "direct_apply"
    assert resolve_write_mode("create_file", "review") == "review"
