"""Tests for agent text serialization."""

from services.document_agent_text import apply_agent_text, document_to_agent_text, parse_agent_text
from services.document_v3 import serialize_document


def test_document_to_agent_text_task_list():
    body = serialize_document(
        {
            "version": 3,
            "blocks": [
                {"id": "b1", "type": "paragraph", "text": "Notes", "spans": []},
                {"id": "b2", "type": "embed", "object_id": 42},
            ],
        }
    )
    text = document_to_agent_text(
        body,
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


def test_apply_agent_text_preserves_unknown_objects():
    body = serialize_document(
        {
            "version": 3,
            "blocks": [
                {"id": "b1", "type": "embed", "object_id": 99},
            ],
        }
    )
    doc, errors = apply_agent_text(
        body,
        "Some text",
        known_object_ids={99},
    )
    assert errors
    assert "missing object id 99" in errors[0]


def test_parse_agent_text_info():
    parsed = parse_agent_text('[INFO id="17"]\nHello info\n[/INFO]')
    assert parsed["object_updates"][17]["body"] == "Hello info"
