"""Tests for JSON document body codec — re-exports v3 tests."""

from areas.files.services.document_v3 import (
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
    from areas.files.services.document_marker_text import (
        DOCUMENT_TEXT_HEADER,
        embed_ids_in_text,
        strip_header,
    )

    body = empty_document_json()
    updated = insert_embed_block(body, 42, block_index=0, object_type="info")
    assert updated.startswith(DOCUMENT_TEXT_HEADER)
    assert embed_ids_in_text(strip_header(updated)) == {42}


def test_migrate_v1_nodes():
    nodes = [
        {"id": "n1", "type": "paragraph", "text": "Title", "spans": []},
        {"id": "n2", "type": "object", "object_type": "task_list", "object_id": 9},
    ]
    doc = migrate_v1_nodes_to_v3(nodes)
    assert doc["blocks"][0]["text"] == "Title"


def test_new_file_default_is_v4_editor_text():
    from areas.files.services.document_marker_text import DOCUMENT_TEXT_HEADER

    assert empty_document_json().startswith(DOCUMENT_TEXT_HEADER)
