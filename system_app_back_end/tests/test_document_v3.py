"""Tests for JSON document codec (v3 block tree)."""

import json

from services.document_v3 import (
    empty_document_json,
    insert_embed_block,
    insert_region,
    migrate_v1_nodes_to_v3,
    move_embed_block,
    parse_document,
    remove_object_embeds,
    serialize_document,
)


def test_empty_document():
    doc = parse_document("")
    assert doc["version"] == 3
    assert doc["blocks"] == []


def test_paragraph_round_trip():
    body = serialize_document(
        {
            "version": 3,
            "blocks": [
                {
                    "id": "b1",
                    "type": "paragraph",
                    "text": "Hello",
                    "spans": [{"start": 0, "end": 5, "bold": True}],
                }
            ],
        }
    )
    doc = parse_document(body)
    assert doc["blocks"][0]["text"] == "Hello"
    assert doc["blocks"][0]["spans"][0]["bold"] is True


def test_insert_embed_block():
    body = empty_document_json()
    updated = insert_embed_block(body, 42, block_index=0)
    doc = parse_document(updated)
    assert doc["blocks"][0]["type"] == "embed"
    assert doc["blocks"][0]["object_id"] == 42


def test_remove_object_embeds():
    body = serialize_document(
        {
            "version": 3,
            "blocks": [
                {"id": "b1", "type": "paragraph", "text": "x", "spans": []},
                {"id": "b2", "type": "embed", "object_id": 5},
                {"id": "b3", "type": "paragraph", "text": "y", "spans": []},
            ],
        }
    )
    updated = remove_object_embeds(body, 5)
    doc = parse_document(updated)
    assert len(doc["blocks"]) == 2
    assert all(b.get("type") != "embed" for b in doc["blocks"])


def test_migrate_plain_text():
    body = "Hello\n\n{{info:3}}\n"
    doc = parse_document(body)
    assert any(
        b.get("type") == "embed" and b.get("object_id") == 3 for b in doc["blocks"]
    )


def test_migrate_v1_nodes():
    nodes = [
        {"id": "n1", "type": "paragraph", "text": "Title", "spans": []},
        {"id": "n2", "type": "object", "object_type": "task_list", "object_id": 9},
    ]
    doc = migrate_v1_nodes_to_v3(nodes)
    assert doc["blocks"][0]["text"] == "Title"
    assert doc["blocks"][1]["object_id"] == 9


def test_insert_list_block():
    body = empty_document_json()
    updated = insert_region(
        body,
        {"id": "r1", "kind": "list", "list_style": "bullet"},
        offset=0,
    )
    doc = parse_document(updated)
    assert doc["blocks"][0]["type"] == "bullet_list"


def test_move_embed_block():
    body = serialize_document(
        {
            "version": 3,
            "blocks": [
                {"id": "b1", "type": "paragraph", "text": "a", "spans": []},
                {"id": "b2", "type": "embed", "object_id": 1},
                {"id": "b3", "type": "paragraph", "text": "b", "spans": []},
            ],
        }
    )
    updated = move_embed_block(body, "b2", 2)
    doc = parse_document(updated)
    assert doc["blocks"][2]["id"] == "b2"


def test_list_block_normalization():
    body = serialize_document(
        {
            "version": 3,
            "blocks": [
                {
                    "id": "b1",
                    "type": "list",
                    "list_style": "numbered",
                    "items": [{"id": "li1", "text": "One", "indent": 0, "spans": []}],
                }
            ],
        }
    )
    doc = parse_document(body)
    assert doc["blocks"][0]["type"] == "ordered_list"


def test_span_color_round_trip():
    body = serialize_document(
        {
            "version": 3,
            "blocks": [
                {
                    "id": "b1",
                    "type": "paragraph",
                    "text": "Red",
                    "spans": [{"start": 0, "end": 3, "color": "#E53935"}],
                }
            ],
        }
    )
    doc = parse_document(body)
    assert doc["blocks"][0]["spans"][0]["color"] == "#E53935"


def test_migrate_v2_inline():
    body = json.dumps(
        {
            "version": 2,
            "text": "Title\uFFFC",
            "spans": [],
            "regions": [],
            "embeds": [
                {
                    "id": "e1",
                    "kind": "object",
                    "object_type": "task_list",
                    "object_id": 9,
                    "offset": 5,
                }
            ],
        }
    )
    doc = parse_document(body)
    assert doc["version"] == 3
    assert doc["blocks"][0]["text"] == "Title"
    assert doc["blocks"][1]["object_id"] == 9


def test_new_file_default_is_v3():
    data = json.loads(empty_document_json())
    assert data["version"] == 3
    assert "blocks" in data
