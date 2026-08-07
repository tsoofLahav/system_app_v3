"""Tests for agent text serialization."""

from unittest.mock import MagicMock, patch

from areas.production_agent.services.write_tools import apply_document_text
from areas.files.services.document_agent_text import (
    apply_agent_text,
    apply_agent_text_to_file,
    document_to_agent_text,
    parse_agent_text,
)
from areas.files.services.document_v3 import serialize_document


def _sample_doc_with_embed():
    return serialize_document(
        {
            "version": 3,
            "blocks": [
                {"id": "b1", "type": "paragraph", "text": "Notes", "spans": []},
                {"id": "b2", "type": "embed", "object_id": 42},
            ],
        }
    )


def test_document_to_agent_text_task_list():
    text = document_to_agent_text(
        _sample_doc_with_embed(),
        objects_by_id={
            42: {
                "type": "task_list",
                "tasks": [
                    {"title": "Call clinic", "status": "active", "list_order_index": 0},
                    {"title": "Find phone", "status": "done", "list_order_index": 0},
                ],
            }
        },
    )
    assert "Notes" in text
    assert '[TASK_LIST id="42"]' in text
    assert "- [ ] Call clinic" in text
    assert "- [x] Find phone" in text


def test_document_to_agent_text_lists_and_table():
    body = serialize_document(
        {
            "version": 3,
            "blocks": [
                {"id": "b1", "type": "heading", "level": 2, "text": "Goals", "spans": []},
                {
                    "id": "b2",
                    "type": "bullet_list",
                    "items": [{"id": "li1", "text": "One", "indent": 0, "spans": []}],
                },
                {
                    "id": "b3",
                    "type": "ordered_list",
                    "items": [{"id": "li2", "text": "First", "indent": 0, "spans": []}],
                },
                {
                    "id": "b4",
                    "type": "table",
                    "rows": [[{"text": "A", "spans": []}, {"text": "B", "spans": []}]],
                },
            ],
        }
    )
    text = document_to_agent_text(body)
    assert "## Goals" in text
    assert "[BULLET_LIST]" in text
    assert "- One" in text
    assert "[/BULLET_LIST]" in text
    assert "[ORDERED_LIST]" in text
    assert "1. First" in text
    assert "[TABLE]" in text
    assert "A\tB" in text
    assert "[/TABLE]" in text


def test_empty_paragraphs_round_trip_as_spacer_markers():
    """Mapper-only: empty paragraphs ↔ [SPACER]; no document spacer type."""
    original = serialize_document(
        {
            "version": 3,
            "blocks": [
                {"id": "b1", "type": "paragraph", "text": "Breakfast", "spans": []},
                {"id": "b2", "type": "paragraph", "text": "", "spans": []},
                {"id": "b3", "type": "paragraph", "text": "", "spans": []},
                {"id": "b4", "type": "paragraph", "text": "Lunch", "spans": []},
            ],
        }
    )
    text = document_to_agent_text(original)
    assert '[SPACER n="2"]' in text
    doc, _, errors = apply_agent_text(original, text, known_object_ids=set())
    assert not errors
    assert all(b["type"] != "spacer" for b in doc["blocks"])
    empties = [b for b in doc["blocks"] if b["type"] == "paragraph" and b["text"] == ""]
    assert len(empties) == 2


def test_blank_lines_inside_paragraph_become_spacer_markers():
    original = serialize_document(
        {
            "version": 3,
            "blocks": [
                {
                    "id": "b1",
                    "type": "paragraph",
                    "text": "Breakfast\n\n\n\nLunch",
                    "spans": [],
                },
            ],
        }
    )
    text = document_to_agent_text(original)
    assert '[SPACER n="1"]' in text
    doc, _, errors = apply_agent_text(original, text, known_object_ids=set())
    assert not errors
    assert all(b["type"] != "spacer" for b in doc["blocks"])
    texts = [b["text"] for b in doc["blocks"] if b["type"] == "paragraph"]
    assert "Breakfast" in texts and "Lunch" in texts
    assert any(t == "" for t in texts)


def test_empty_file_agent_text_is_empty():
    original = serialize_document(
        {
            "version": 3,
            "blocks": [{"id": "b1", "type": "paragraph", "text": "", "spans": []}],
        }
    )
    assert document_to_agent_text(original) == ""


def test_parse_spacer_becomes_empty_paragraphs():
    parsed = parse_agent_text("Above\n\n[SPACER]\n\nBelow")
    assert parsed["blocks"][0]["text"] == "Above"
    assert parsed["blocks"][-1]["text"] == "Below"
    assert parsed["blocks"][1]["type"] == "paragraph"
    assert parsed["blocks"][1]["text"] == ""


def test_text_to_blocks_empty_runs_become_empty_paragraphs():
    parsed = parse_agent_text("A\n\n\n\nB")
    assert [b["type"] for b in parsed["blocks"]] == [
        "paragraph",
        "paragraph",
        "paragraph",
    ]
    assert parsed["blocks"][1]["text"] == ""


def test_legacy_spacer_type_normalizes_to_empty_paragraphs():
    from areas.files.services.document_v3 import _normalize_v3

    norm = _normalize_v3(
        {
            "version": 3,
            "blocks": [
                {"id": "b1", "type": "paragraph", "text": "A", "spans": []},
                {"id": "b2", "type": "spacer", "n": 2},
                {"id": "b3", "type": "paragraph", "text": "B", "spans": []},
            ],
        }
    )
    assert all(b["type"] != "spacer" for b in norm["blocks"])
    empties = [b for b in norm["blocks"] if b["type"] == "paragraph" and b["text"] == ""]
    assert len(empties) == 2


def test_round_trip_paragraph_heading_list_table_task_list():
    objects = {
        42: {
            "type": "task_list",
            "tasks": [{"title": "Todo", "status": "active", "list_order_index": 0}],
        }
    }
    original = serialize_document(
        {
            "version": 3,
            "blocks": [
                {"id": "b1", "type": "paragraph", "text": "Intro", "spans": []},
                {"id": "b2", "type": "heading", "level": 2, "text": "Section", "spans": []},
                {
                    "id": "b3",
                    "type": "bullet_list",
                    "items": [{"id": "li1", "text": "Item", "indent": 0, "spans": []}],
                },
                {
                    "id": "b4",
                    "type": "table",
                    "rows": [[{"text": "x", "spans": []}, {"text": "y", "spans": []}]],
                },
                {"id": "b5", "type": "embed", "object_id": 42},
            ],
        }
    )
    agent_text = document_to_agent_text(original, objects_by_id=objects)
    doc, object_updates, errors = apply_agent_text(original, agent_text, known_object_ids={42})
    assert not errors
    assert doc["version"] == 3
    types = [b["type"] for b in doc["blocks"]]
    assert "paragraph" in types
    assert "heading" in types
    assert "bullet_list" in types
    assert "table" in types
    assert "embed" in types
    assert object_updates[42]["type"] == "task_list"


def test_table_tab_escaping_round_trip():
    body = serialize_document(
        {
            "version": 3,
            "blocks": [
                {
                    "id": "b1",
                    "type": "table",
                    "rows": [[{"text": "a\tb", "spans": []}, {"text": "plain", "spans": []}]],
                }
            ],
        }
    )
    text = document_to_agent_text(body)
    assert "a\\tb" in text
    doc, _, errors = apply_agent_text(body, text, known_object_ids=set())
    assert not errors
    cell = doc["blocks"][0]["rows"][0][0]["text"]
    assert cell == "a\tb"


def test_apply_agent_text_preserves_unknown_objects():
    body = serialize_document(
        {
            "version": 3,
            "blocks": [{"id": "b1", "type": "embed", "object_id": 99}],
        }
    )
    _, _, errors = apply_agent_text(body, "Some text", known_object_ids={99})
    assert errors
    assert "missing object id 99" in errors[0]


def test_apply_agent_text_rejects_unknown_object_id():
    body = serialize_document({"version": 3, "blocks": []})
    _, _, errors = apply_agent_text(
        body,
        '[INFO id="17"]\nHello\n[/INFO]',
        known_object_ids=set(),
    )
    assert errors
    assert "unknown object id: 17" in errors[0]


def test_parse_agent_text_info_legacy_body_only():
    parsed = parse_agent_text('[INFO id="17"]\nHello info\n[/INFO]')
    assert parsed["object_updates"][17]["body"] == "Hello info"
    assert "title" not in parsed["object_updates"][17]


def test_info_title_body_round_trip():
    objects = {
        17: {
            "type": "info",
            "information": {"title": "Lens notes", "body": "Practice daily.\nTrack weekly."},
        }
    }
    original = serialize_document(
        {"version": 3, "blocks": [{"id": "b1", "type": "embed", "object_id": 17}]}
    )
    text = document_to_agent_text(original, objects_by_id=objects)
    assert '[INFO id="17"]' in text
    assert "Lens notes\nPractice daily.\nTrack weekly." in text
    parsed = parse_agent_text(text)
    assert parsed["object_updates"][17]["title"] == "Lens notes"
    assert parsed["object_updates"][17]["body"] == "Practice daily.\nTrack weekly."
    doc, updates, errors = apply_agent_text(original, text, known_object_ids={17})
    assert not errors
    assert updates[17]["title"] == "Lens notes"


def test_graph_table_round_trip():
    objects = {
        8: {
            "type": "graph",
            "payload": {
                "labels": ["A", "B"],
                "values": ["1", "2"],
                "chartType": "bar",
                "colors": ["#111111", "#222222"],
            },
        }
    }
    original = serialize_document(
        {"version": 3, "blocks": [{"id": "b1", "type": "embed", "object_id": 8}]}
    )
    text = document_to_agent_text(original, objects_by_id=objects)
    assert 'chartType="bar"' in text
    assert "A\tB" in text
    assert "1\t2" in text
    assert "#111111\t#222222" in text
    assert "[/GRAPH]" in text
    parsed = parse_agent_text(text)
    payload = parsed["object_updates"][8]["payload"]
    assert payload["chartType"] == "bar"
    assert payload["labels"] == ["A", "B"]
    assert payload["values"] == ["1", "2"]
    assert payload["colors"] == ["#111111", "#222222"]


def test_image_caption_and_url():
    objects = {
        5: {
            "type": "image",
            "payload": {"caption": "Shot", "url": "/uploads/a.png"},
        }
    }
    original = serialize_document(
        {"version": 3, "blocks": [{"id": "b1", "type": "embed", "object_id": 5}]}
    )
    text = document_to_agent_text(original, objects_by_id=objects)
    assert 'caption="Shot"' in text
    assert 'url="/uploads/a.png"' in text
    parsed = parse_agent_text(text)
    assert parsed["object_updates"][5]["payload"]["caption"] == "Shot"
    assert parsed["object_updates"][5]["payload"]["url"] == "/uploads/a.png"


def test_parse_agent_text_bullet_list_and_table():
    parsed = parse_agent_text(
        "[BULLET_LIST]\n- Alpha\n- Beta\n[/BULLET_LIST]\n\n"
        "[TABLE]\nH1\tH2\nV1\tV2\n[/TABLE]"
    )
    types = [b["type"] for b in parsed["blocks"]]
    assert "bullet_list" in types
    assert "table" in types
    list_block = next(b for b in parsed["blocks"] if b["type"] == "bullet_list")
    assert [i["text"] for i in list_block["items"]] == ["Alpha", "Beta"]
    table = next(b for b in parsed["blocks"] if b["type"] == "table")
    assert table["rows"][0][0]["text"] == "H1"
    assert table["rows"][1][1]["text"] == "V2"


@patch("areas.production_agent.services.write_tools.apply_object_updates", return_value=[])
@patch("areas.production_agent.services.write_tools.save_file_version")
@patch("areas.production_agent.services.write_tools.db.session")
@patch("areas.production_agent.services.write_tools.ObjectEmbed")
def test_apply_document_text_direct_apply(
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

    agent_text = "## Title\n\nHello world"
    result = apply_document_text(
        1,
        agent_text,
        scope={"file_ids": [1]},
        write_mode="direct_apply",
        tool_name="patch_file",
    )

    assert result.get("applied") is True
    assert "Title" in (file_row.document_json or "")
    mock_apply_objects.assert_called_once()


@patch("areas.production_agent.services.write_tools.db.session")
@patch("areas.production_agent.services.write_tools.ObjectEmbed")
def test_apply_document_text_review_returns_agent_text_diff(
    mock_embed_model, mock_session
):
    file_row = MagicMock()
    file_row.id = 1
    file_row.topic_id = 1
    file_row.archived_at = None
    file_row.document_json = serialize_document(
        {
            "version": 3,
            "blocks": [{"id": "b1", "type": "paragraph", "text": "Before", "spans": []}],
        }
    )
    mock_session.get.return_value = file_row
    mock_embed_model.query.filter_by.return_value.all.return_value = []

    result = apply_document_text(
        1,
        "After text",
        scope={"file_ids": [1]},
        write_mode="review",
        tool_name="patch_file",
    )

    assert result.get("applied") is False
    assert "review" in result
    assert "old_document_text" in result["review"]
    assert "new_document_text" in result["review"]


def test_apply_agent_text_to_file_no_embeds():
    serialized, updates, errors = apply_agent_text_to_file(
        1,
        serialize_document({"version": 3, "blocks": []}),
        "## Hello\n\nWorld",
        known_object_ids=set(),
    )
    assert not errors
    assert updates == {}
    assert serialized is not None
    assert "Hello" in serialized
