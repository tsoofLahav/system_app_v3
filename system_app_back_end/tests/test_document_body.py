"""Tests for JSON document body codec — re-exports v3 tests."""

from services.document_v3 import (
    empty_document_json,
    insert_embed_block,
    migrate_v1_nodes_to_v3,
    parse_document,
    serialize_document,
)


def test_empty_document():
    doc = parse_document("")
    assert doc["version"] == 3


def test_paragraph_round_trip():
    body = serialize_document(
        {
            "version": 3,
            "blocks": [
                {"id": "b1", "type": "paragraph", "text": "Hello", "spans": []},
            ],
        }
    )
    doc = parse_document(body)
    assert doc["blocks"][0]["text"] == "Hello"


def test_insert_object_embed():
    body = empty_document_json()
    updated = insert_embed_block(body, 42, block_index=0)
    doc = parse_document(updated)
    assert doc["blocks"][0]["object_id"] == 42


def test_migrate_v1_nodes():
    nodes = [
        {"id": "n1", "type": "paragraph", "text": "Title", "spans": []},
        {"id": "n2", "type": "object", "object_type": "task_list", "object_id": 9},
    ]
    doc = migrate_v1_nodes_to_v3(nodes)
    assert doc["blocks"][0]["text"] == "Title"


def test_new_file_default_is_v3():
    import json

    data = json.loads(empty_document_json())
    assert data["version"] == 3
