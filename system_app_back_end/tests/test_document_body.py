"""Tests for JSON document body codec."""

import json

from services.document_body import (
    document_plain_text,
    empty_document_json,
    insert_node,
    object_node_for,
    parse_document,
    remove_object_nodes,
    serialize_document,
)


def test_empty_document():
    doc = parse_document("")
    assert doc["version"] == 1
    assert doc["nodes"] == []


def test_paragraph_round_trip():
    body = serialize_document(
        {
            "version": 1,
            "nodes": [
                {
                    "id": "n1",
                    "type": "paragraph",
                    "text": "Hello",
                    "spans": [{"start": 0, "end": 5, "bold": True}],
                }
            ],
        }
    )
    doc = parse_document(body)
    assert doc["nodes"][0]["text"] == "Hello"
    assert doc["nodes"][0]["spans"][0]["bold"] is True


def test_insert_object_node():
    body = empty_document_json()
    node = object_node_for(42, "task_list", node_id="n7")
    updated = insert_node(body, node)
    doc = parse_document(updated)
    assert doc["nodes"][0]["object_id"] == 42
    assert doc["nodes"][0]["object_type"] == "task_list"


def test_remove_object_nodes():
    body = serialize_document(
        {
            "version": 1,
            "nodes": [
                object_node_for(5, "info"),
                {"id": "n2", "type": "paragraph", "text": "x", "spans": []},
            ],
        }
    )
    updated = remove_object_nodes(body, 5)
    doc = parse_document(updated)
    assert len(doc["nodes"]) == 1
    assert doc["nodes"][0]["type"] == "paragraph"


def test_migrate_plain_text():
    body = "Hello\n\n{{info:3}}\n"
    doc = parse_document(body)
    assert doc["nodes"][0]["type"] == "paragraph"
    assert doc["nodes"][0]["text"] == "Hello"
    assert doc["nodes"][-1]["type"] == "object"
    assert doc["nodes"][-1]["object_id"] == 3


def test_document_plain_text():
    body = serialize_document(
        {
            "version": 1,
            "nodes": [
                {"id": "n1", "type": "paragraph", "text": "Title", "spans": []},
                object_node_for(9, "task_list"),
            ],
        }
    )
    plain = document_plain_text(body)
    assert "Title" in plain
    assert "[task_list #9]" in plain


def test_new_file_default_is_json():
    data = json.loads(empty_document_json())
    assert "nodes" in data
