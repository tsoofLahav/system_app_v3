"""Tests for JSON document body codec (v2 inline)."""

import json

from services.document_body import (
    EMBED_CHAR,
    document_plain_text,
    empty_document_json,
    insert_embed,
    insert_region,
    migrate_v1_nodes_to_v2,
    move_embed,
    object_node_for,
    parse_document,
    remove_object_embeds,
    serialize_document,
)


def test_empty_document():
    doc = parse_document("")
    assert doc["version"] == 2
    assert doc["text"] == ""
    assert doc["embeds"] == []


def test_paragraph_round_trip():
    body = serialize_document(
        {
            "version": 2,
            "text": "Hello",
            "spans": [{"start": 0, "end": 5, "bold": True}],
            "regions": [],
            "embeds": [],
        }
    )
    doc = parse_document(body)
    assert doc["text"] == "Hello"
    assert doc["spans"][0]["bold"] is True


def test_insert_object_embed():
    body = empty_document_json()
    embed = object_node_for(42, "task_list")
    updated = insert_embed(body, embed, offset=0)
    doc = parse_document(updated)
    assert doc["text"] == EMBED_CHAR
    assert doc["embeds"][0]["object_id"] == 42
    assert doc["embeds"][0]["object_type"] == "task_list"


def test_remove_object_embeds():
    body = serialize_document(
        {
            "version": 2,
            "text": f"x{EMBED_CHAR}y",
            "spans": [],
            "regions": [],
            "embeds": [object_node_for(5, "info", node_id="e1") | {"offset": 1}],
        }
    )
    updated = remove_object_embeds(body, 5)
    doc = parse_document(updated)
    assert doc["text"] == "xy"
    assert doc["embeds"] == []


def test_migrate_plain_text():
    body = "Hello\n\n{{info:3}}\n"
    doc = parse_document(body)
    assert "Hello" in doc["text"]
    assert any(e.get("object_id") == 3 for e in doc["embeds"])


def test_migrate_v1_nodes():
    nodes = [
        {"id": "n1", "type": "paragraph", "text": "Title", "spans": []},
        {"id": "n2", "type": "object", "object_type": "task_list", "object_id": 9},
    ]
    doc = migrate_v1_nodes_to_v2(nodes)
    assert "Title" in doc["text"]
    assert any(e.get("object_id") == 9 for e in doc["embeds"])


def test_document_plain_text():
    body = serialize_document(
        {
            "version": 2,
            "text": f"Title{EMBED_CHAR}",
            "spans": [],
            "regions": [],
            "embeds": [object_node_for(9, "task_list") | {"offset": 5}],
        }
    )
    plain = document_plain_text(body)
    assert "Title" in plain
    assert "[task_list #9]" in plain


def test_insert_list_region():
    body = empty_document_json()
    updated = insert_region(
        body,
        {"id": "r1", "kind": "list", "list_style": "bullet"},
        offset=0,
    )
    doc = parse_document(updated)
    assert len(doc["regions"]) == 1
    assert doc["regions"][0]["kind"] == "list"


def test_move_embed():
    body = serialize_document(
        {
            "version": 2,
            "text": f"ab{EMBED_CHAR}cd",
            "spans": [],
            "regions": [],
            "embeds": [
                {
                    "id": "e1",
                    "kind": "image",
                    "offset": 2,
                    "url": "http://x",
                }
            ],
        }
    )
    updated = move_embed(body, "e1", 4)
    doc = parse_document(updated)
    assert doc["embeds"][0]["offset"] == 4


def test_new_file_default_is_v2():
    data = json.loads(empty_document_json())
    assert data["version"] == 2
    assert "text" in data
