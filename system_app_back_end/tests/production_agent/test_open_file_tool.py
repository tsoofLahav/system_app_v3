"""Tests for open_file tool payload extras."""

from unittest.mock import MagicMock, patch

from areas.production_agent.services.open_file_tool import (
    _info_extra,
    build_open_file_payload,
)


def test_info_extra_includes_title_and_links():
    obj = {"type": "info", "information": {"title": "Lens notes", "body": "…"}}
    with patch(
        "areas.production_agent.services.open_file_tool._info_links",
        return_value=[
            {"id": 22, "type": "info", "title": "Related", "file_id": 9},
            {"id": 11, "type": "file", "title": "Text", "kind": "description"},
        ],
    ):
        extra = _info_extra(17, obj)
    assert extra == {
        "object_id": 17,
        "type": "info",
        "title": "Lens notes",
        "Links": [
            {"id": 22, "type": "info", "title": "Related", "file_id": 9},
            {"id": 11, "type": "file", "title": "Text", "kind": "description"},
        ],
    }


def test_info_extra_omitted_when_empty():
    with patch(
        "areas.production_agent.services.open_file_tool._info_links",
        return_value=[],
    ):
        assert _info_extra(17, {"type": "info", "information": {}}) is None


def test_build_open_file_payload_shape():
    file = MagicMock()
    file.id = 12
    file.name = "Vision plan"
    file.topic_id = 3
    file.archived_at = None
    file.document_json = "{}"

    with (
        patch(
            "areas.production_agent.services.open_file_tool.load_objects_by_id",
            return_value={
                17: {
                    "type": "info",
                    "information": {"title": "Goals", "body": "Practice daily"},
                },
                42: {"type": "task_list", "tasks": []},
            },
        ),
        patch(
            "areas.production_agent.services.open_file_tool.document_to_agent_text",
            return_value='[INFO id="17"]\nPractice daily\n[/INFO]',
        ),
        patch(
            "areas.production_agent.services.open_file_tool._info_links",
            return_value=[{"id": 22, "type": "info", "title": "Peer"}],
        ),
        patch(
            "areas.production_agent.services.open_file_tool._topic_name",
            return_value="vision",
        ),
    ):
        payload = build_open_file_payload(file)

    assert payload["id"] == 12
    assert payload["archived"] is False
    # The agent must see which topic it opened, not just a topic_id.
    assert payload["topic"] == "vision"
    assert "document_plain" in payload
    assert '[INFO id="17"]' in payload["document_plain"]
    assert payload["document_lines"] == [
        {"line": 1, "text": '[INFO id="17"]'},
        {"line": 2, "text": "Practice daily"},
        {"line": 3, "text": "[/INFO]"},
    ]
    # No ORM dump of every object — only useful extras
    assert "objects" not in payload
    assert payload["object_extras"] == [
        {
            "object_id": 17,
            "type": "info",
            "title": "Goals",
            "Links": [{"id": 22, "type": "info", "title": "Peer"}],
        }
    ]


def test_build_open_file_marks_archived():
    file = MagicMock()
    file.id = 5
    file.name = "Old"
    file.topic_id = 1
    file.archived_at = object()
    file.document_json = ""

    with (
        patch(
            "areas.production_agent.services.open_file_tool.load_objects_by_id",
            return_value={},
        ),
        patch(
            "areas.production_agent.services.open_file_tool.document_to_agent_text",
            return_value="",
        ),
        patch(
            "areas.production_agent.services.open_file_tool._topic_name",
            return_value="vision",
        ),
    ):
        payload = build_open_file_payload(file)

    assert payload["archived"] is True
    assert payload["object_extras"] == []
