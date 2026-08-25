"""Tests for v4 editor-text (pointer markers) storage."""

from areas.files.services.document_agent_text import (
    apply_agent_text_to_file,
    document_to_agent_text,
    editor_text_to_agent_text,
)
from areas.files.services.document_marker_text import (
    DOCUMENT_TEXT_HEADER,
    embed_ids_in_text,
    ensure_editor_text,
    insert_embed_pointer,
    migrate_v3_json_to_editor_text,
    move_embed_pointer,
    pointer_line,
    remove_embed_pointers,
    strip_header,
    rewrite_pointer_ids,
    wrap_editor_text,
)
from areas.files.services.document_v3 import serialize_document


def test_migrate_v3_embeds_become_pointers_only():
    body = serialize_document(
        {
            "version": 3,
            "blocks": [
                {"id": "b1", "type": "paragraph", "text": "Hello", "spans": []},
                {"id": "b2", "type": "embed", "object_id": 42},
                {"id": "b3", "type": "paragraph", "text": "World", "spans": []},
            ],
        }
    )
    text = migrate_v3_json_to_editor_text(
        body,
        objects_by_id={42: {"type": "info"}},
    )
    assert text.startswith(DOCUMENT_TEXT_HEADER)
    body_only = strip_header(text)
    assert "Hello" in body_only
    assert '[INFO id="42"]' in body_only
    assert "[/INFO]" not in body_only
    assert "World" in body_only
    assert embed_ids_in_text(body_only) == {42}


def test_move_embed_pointer_reorders_without_split():
    text = wrap_editor_text('Hello\n\n[INFO id="9"]\n\nWorld')
    moved = move_embed_pointer(text, 9, gap_index=0)
    parts = strip_header(moved).split("\n\n")
    assert parts[0] == '[INFO id="9"]'
    assert "Hello" in parts[1]
    assert "World" in parts[2]


def test_insert_and_remove_pointer():
    text = wrap_editor_text("Notes")
    with_embed = insert_embed_pointer(text, 7, object_type="task_list", block_index=1)
    assert '[TASK_LIST id="7"]' in strip_header(with_embed)
    cleared = remove_embed_pointers(with_embed, 7)
    assert "7" not in strip_header(cleared)
    assert "Notes" in strip_header(cleared)


def test_agent_expand_and_collapse_round_trip():
    editor = wrap_editor_text('Intro\n\n[INFO id="17"]')
    agent = editor_text_to_agent_text(
        editor,
        objects_by_id={
            17: {
                "type": "info",
                "information": {"title": "Lens", "body": "Practice daily."},
            }
        },
    )
    assert "[/INFO]" in agent
    assert "Lens" in agent
    assert "Practice daily." in agent

    out, updates, errors = apply_agent_text_to_file(
        1,
        editor,
        agent,
        known_object_ids={17},
    )
    assert errors == []
    assert out is not None
    assert out.startswith(DOCUMENT_TEXT_HEADER)
    assert '[INFO id="17"]' in strip_header(out)
    assert "[/INFO]" not in strip_header(out)
    assert updates[17]["title"] == "Lens"


def test_document_to_agent_text_accepts_v3_and_v4():
    v3 = serialize_document(
        {
            "version": 3,
            "blocks": [
                {"id": "b1", "type": "paragraph", "text": "Notes", "spans": []},
                {"id": "b2", "type": "embed", "object_id": 42},
            ],
        }
    )
    objects = {
        42: {
            "type": "task_list",
            "tasks": [
                {"title": "Call", "status": "active", "list_order_index": 0},
            ],
        }
    }
    from_v3 = document_to_agent_text(v3, objects_by_id=objects)
    assert "- [ ] Call" in from_v3

    v4 = ensure_editor_text(v3, objects_by_id=objects)
    from_v4 = document_to_agent_text(v4, objects_by_id=objects)
    assert "- [ ] Call" in from_v4


def test_pointer_line_helpers():
    assert pointer_line(3, "graph") == '[GRAPH id="3"]'
    assert pointer_line(3, None) == '[EMBED id="3"]'


def test_rewrite_pointer_ids_maps_old_to_new():
    body = wrap_editor_text('[INFO id="4"]\n\nHello\n\n[TABLE id="9"]')
    out = rewrite_pointer_ids(body, {4: 40, 9: 90})
    assert '[INFO id="40"]' in out
    assert '[TABLE id="90"]' in out
    assert '[INFO id="4"]' not in out
