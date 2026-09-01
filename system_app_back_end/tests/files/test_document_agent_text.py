"""Tests for agent text serialization."""

from unittest.mock import MagicMock, patch

from areas.production_agent.services.write_tools import apply_document_text
from areas.files.services.document_agent_text import (
    agent_text_to_editor_text,
    apply_agent_text,
    apply_agent_text_to_file,
    document_to_agent_text,
    pair_task_list_updates,
    parse_agent_text,
    _sync_task_list,
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


def test_document_to_agent_text_pending_and_inactive():
    text = document_to_agent_text(
        _sample_doc_with_embed(),
        objects_by_id={
            42: {
                "type": "task_list",
                "tasks": [
                    {"title": "Now", "status": "active", "list_order_index": 0},
                    {"title": "Later", "status": "pending", "list_order_index": 1},
                    {"title": "Parked", "status": "inactive", "list_order_index": 2},
                ],
            }
        },
    )
    assert "PENDING:" in text
    assert "INACTIVE:" in text
    parsed = parse_agent_text(text)
    by_title = {t["title"]: t["status"] for t in parsed["object_updates"][42]["tasks"]}
    assert by_title == {"Now": "active", "Later": "pending", "Parked": "inactive"}


def test_task_list_title_round_trip():
    text = document_to_agent_text(
        _sample_doc_with_embed(),
        objects_by_id={
            42: {
                "type": "task_list",
                "title": "Week",
                "tasks": [
                    {"title": "Call clinic", "status": "active", "list_order_index": 0},
                ],
            }
        },
    )
    assert '[TASK_LIST id="42" title="Week"]' in text
    parsed = parse_agent_text(text)
    assert parsed["object_updates"][42]["title"] == "Week"
    assert parsed["object_updates"][42]["tasks"][0]["title"] == "Call clinic"


def test_task_list_legacy_fence_leaves_title_alone():
    parsed = parse_agent_text(
        '[TASK_LIST id="42"]\nACTIVE:\n- [ ] A\nDONE:\n[/TASK_LIST]'
    )
    assert "title" not in parsed["object_updates"][42]


def test_task_list_empty_title_attr_clears_header():
    parsed = parse_agent_text(
        '[TASK_LIST id="42" title=""]\nACTIVE:\nDONE:\n[/TASK_LIST]'
    )
    assert parsed["object_updates"][42]["title"] == ""


class _Row:
    def __init__(self, title, *, status="active", task_id=None, due_date="keep"):
        self.id = task_id
        self.title = title
        self.status = status
        self.due_date = due_date
        self.list_order_index = 0
        self.archived_at = None


def test_pair_task_list_updates_title_match_survives_reorder():
    existing = [_Row("A", task_id=1), _Row("B", task_id=2), _Row("C", task_id=3)]
    incoming = [
        {"title": "C", "status": "active", "list_order_index": 0},
        {"title": "A", "status": "active", "list_order_index": 1},
        {"title": "B", "status": "done", "list_order_index": 2},
    ]
    updates, creates, deletes = pair_task_list_updates(existing, incoming)
    assert {task.id for task, _ in updates} == {1, 2, 3}
    by_id = {task.id: item["title"] for task, item in updates}
    assert by_id == {1: "A", 2: "B", 3: "C"}
    assert creates == []
    assert deletes == []


def test_pair_task_list_updates_full_rewrite_keeps_rows_in_order():
    existing = [_Row("Old A", task_id=11), _Row("Old B", task_id=12)]
    incoming = [
        {"title": "New A", "status": "active", "list_order_index": 0},
        {"title": "New B", "status": "active", "list_order_index": 1},
    ]
    updates, creates, deletes = pair_task_list_updates(existing, incoming)
    assert [task.id for task, _ in updates] == [11, 12]
    assert [item["title"] for _, item in updates] == ["New A", "New B"]
    assert creates == []
    assert deletes == []


def test_pair_task_list_updates_extra_line_creates_and_missing_line_deletes():
    existing = [_Row("Keep", task_id=1), _Row("Drop", task_id=2)]
    incoming = [
        {"title": "Keep", "status": "active", "list_order_index": 0},
        {"title": "Added", "status": "inactive", "list_order_index": 1},
    ]
    updates, creates, deletes = pair_task_list_updates(existing, incoming)
    assert [task.id for task, item in updates] == [1, 2]
    assert [item["title"] for _, item in updates] == ["Keep", "Added"]
    assert creates == []
    assert deletes == []

    only_keep = [{"title": "Keep", "status": "active", "list_order_index": 0}]
    updates, creates, deletes = pair_task_list_updates(existing, only_keep)
    assert [task.id for task, _ in updates] == [1]
    assert creates == []
    assert [task.id for task in deletes] == [2]

    with_extra = only_keep + [
        {"title": "Drop", "status": "active", "list_order_index": 1},
        {"title": "New", "status": "inactive", "list_order_index": 2},
    ]
    updates, creates, deletes = pair_task_list_updates(existing, with_extra)
    assert {task.id for task, _ in updates} == {1, 2}
    assert [item["title"] for item in creates] == ["New"]
    assert deletes == []


def test_sync_task_list_updates_in_place(monkeypatch):
    from areas.files.services import document_agent_text as dat

    keep = _Row("Call clinic", task_id=11, status="pending", due_date="2026-09-10")
    drop = _Row("Find phone", task_id=12)
    created = []
    deleted = []

    class Embed:
        task_list_id = 5

    class FakeSession:
        def get(self, _model, _id):
            return None

        def add(self, row):
            created.append(row)

    monkeypatch.setattr(dat, "tasks_for_list", lambda _id: [keep, drop])
    monkeypatch.setattr(dat, "delete_task_cascade", deleted.append)
    monkeypatch.setattr(dat, "db", type("DB", (), {"session": FakeSession()})())

    _sync_task_list(
        Embed(),
        [
            {"title": "Call doctor", "status": "active", "list_order_index": 0},
        ],
    )
    assert keep.title == "Call doctor"
    assert keep.status == "active"
    assert keep.due_date is None
    assert keep.archived_at is None
    assert deleted == [12]
    assert created == []

    deleted.clear()
    monkeypatch.setattr(dat, "tasks_for_list", lambda _id: [keep])
    _sync_task_list(
        Embed(),
        [
            {"title": "Call doctor", "status": "active", "list_order_index": 0},
            {"title": "Buy stamps", "status": "inactive", "list_order_index": 1},
        ],
    )
    assert keep.title == "Call doctor"
    assert deleted == []
    assert len(created) == 1
    assert created[0].title == "Buy stamps"
    assert created[0].status == "inactive"
    assert created[0].task_list_id == 5


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
    assert "A\\tB" in text
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


def test_single_blank_line_in_paragraph_becomes_spacer():
    """The common stored form: one \\n\\n inside paragraph text (after coalesce)."""
    original = serialize_document(
        {
            "version": 3,
            "blocks": [
                {
                    "id": "b1",
                    "type": "paragraph",
                    "text": "Breakfast\n\nLunch",
                    "spans": [],
                },
            ],
        }
    )
    text = document_to_agent_text(original)
    assert '[SPACER n="1"]' in text
    doc, _, errors = apply_agent_text(original, text, known_object_ids=set())
    assert not errors
    assert any(b.get("text") == "" for b in doc["blocks"])
    # After editor-style coalesce, the blank line is back inside one paragraph.
    coalesced = []
    run = None
    for b in doc["blocks"]:
        if b["type"] == "paragraph":
            if run is None:
                run = b["text"]
            else:
                run = f"{run}\n{b['text']}"
        else:
            if run is not None:
                coalesced.append(run)
                run = None
    if run is not None:
        coalesced.append(run)
    assert any("Breakfast\n\nLunch" == c for c in coalesced)


def test_double_blank_run_in_paragraph_becomes_spacer_n3():
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
    assert '[SPACER n="3"]' in text


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
        11: {
            "type": "table",
            "payload": {"rows": [[{"text": "x"}, {"text": "y"}]]},
        },
        42: {
            "type": "task_list",
            "tasks": [{"title": "Todo", "status": "active", "list_order_index": 0}],
        },
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
                {"id": "b4", "type": "embed", "object_id": 11},
                {"id": "b5", "type": "embed", "object_id": 42},
            ],
        }
    )
    agent_text = document_to_agent_text(original, objects_by_id=objects)
    doc, object_updates, errors = apply_agent_text(
        original, agent_text, known_object_ids={11, 42}
    )
    assert not errors
    assert doc["version"] == 3
    types = [b["type"] for b in doc["blocks"]]
    assert "paragraph" in types
    assert "heading" in types
    assert "bullet_list" in types
    assert types.count("embed") == 2
    assert object_updates[42]["type"] == "task_list"
    assert object_updates[11]["type"] == "table"


def test_table_tab_escaping_round_trip():
    objects = {
        5: {
            "type": "table",
            "payload": {
                "rows": [[{"text": "a\tb"}, {"text": "plain"}]],
            },
        }
    }
    body = serialize_document(
        {
            "version": 3,
            "blocks": [{"id": "b1", "type": "embed", "object_id": 5}],
        }
    )
    text = document_to_agent_text(body, objects_by_id=objects)
    # In-cell tab → \\t; cell separator → visible \t; no raw tab characters.
    assert "a\\\\tb\\tplain" in text
    assert "\t" not in text.split("\n")[1]
    _, updates, errors = apply_agent_text(body, text, known_object_ids={5})
    assert not errors
    cell = updates[5]["payload"]["rows"][0][0]["text"]
    assert cell == "a\tb"
    assert updates[5]["payload"]["rows"][0][1]["text"] == "plain"


def test_table_visible_tab_separator_round_trip():
    objects = {
        8: {
            "type": "table",
            "payload": {
                "rows": [
                    [{"text": "Name"}, {"text": "Qty"}],
                    [{"text": "Eggs"}, {"text": "6"}],
                ],
            },
        }
    }
    body = serialize_document(
        {
            "version": 3,
            "blocks": [{"id": "b1", "type": "embed", "object_id": 8}],
        }
    )
    text = document_to_agent_text(body, objects_by_id=objects)
    assert 'Name\\tQty' in text
    assert "\t" not in text
    _, updates, errors = apply_agent_text(body, text, known_object_ids={8})
    assert not errors
    assert updates[8]["payload"]["rows"][0][0]["text"] == "Name"
    assert updates[8]["payload"]["rows"][1][1]["text"] == "6"

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


def test_unclosed_list_is_rejected_instead_of_becoming_text():
    # Without the guard the parser falls through and the marker is stored as
    # characters, so the file ends up showing `BULLET_LIST]` to the user.
    editor, _, errors = agent_text_to_editor_text(
        "Plan:\n[BULLET_LIST]\n- one\n- two",
        known_object_ids=set(),
    )
    assert editor is None
    assert errors == [
        "line 2: [BULLET_LIST] is never closed — add [/BULLET_LIST] on its "
        "own line, or edit the lines inside the existing one"
    ]


def test_second_list_opened_beside_a_closed_one_is_rejected():
    _, _, errors = agent_text_to_editor_text(
        "[BULLET_LIST]\n- one\n[/BULLET_LIST]\n[BULLET_LIST]\n- added",
        known_object_ids=set(),
    )
    assert errors and "line 4" in errors[0]


def test_list_marker_with_an_attribute_is_rejected_once():
    _, _, errors = agent_text_to_editor_text(
        '[BULLET_LIST id="3"]\n- one\n[/BULLET_LIST]',
        known_object_ids=set(),
    )
    assert errors == [
        "line 1: [BULLET_LIST] takes no attributes — write [BULLET_LIST] on "
        "its own line"
    ]


def test_stray_closer_is_rejected():
    _, _, errors = agent_text_to_editor_text(
        "- one\n[/BULLET_LIST]",
        known_object_ids=set(),
    )
    assert errors and "never opened" in errors[0]


def test_marker_words_inside_a_fence_and_plain_brackets_still_pass():
    _, _, errors = agent_text_to_editor_text(
        '[INFO id="2"]\nTitle\n[BULLET_LIST] is how a list opens\n[/INFO]\n'
        "A line mentioning [IMPORTANT] stays text",
        known_object_ids={2},
    )
    assert errors == []


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


def test_table_object_pointer_round_trip():
    from areas.files.services import document_marker_text as marker_text

    objects = {
        11: {
            "type": "table",
            "payload": {
                "rows": [
                    [{"text": "H1"}, {"text": "H2"}],
                    [{"text": "V1"}, {"text": "V2"}],
                ]
            },
        }
    }
    editor = marker_text.wrap_editor_text('[TABLE id="11"]')
    text = document_to_agent_text(editor, objects_by_id=objects)
    assert '[TABLE id="11"]' in text
    assert "H1\\tH2" in text
    assert "V1\\tV2" in text
    assert "[/TABLE]" in text
    parsed = parse_agent_text(text)
    assert parsed["blocks"][0]["type"] == "embed"
    assert parsed["blocks"][0]["object_id"] == 11
    payload = parsed["object_updates"][11]["payload"]
    assert payload["rows"][0][0]["text"] == "H1"
    assert payload["rows"][1][1]["text"] == "V2"
    collapsed, updates, errors = agent_text_to_editor_text(
        text, known_object_ids={11}, current_body=editor
    )
    assert not errors
    assert '[TABLE id="11"]' in (collapsed or "")
    assert updates[11]["type"] == "table"


def test_graph_table_round_trip():
    """Chart quality on a table object expands/parses as a GRAPH fence."""
    objects = {
        8: {
            "type": "table",
            "payload": {
                "rows": [
                    [{"text": "A"}, {"text": "B"}],
                    [{"text": "1"}, {"text": "2"}],
                ],
                "chart": {
                    "enabled": True,
                    "chartType": "bar",
                    "colors": ["#111111", "#222222"],
                },
            },
        }
    }
    original = serialize_document(
        {"version": 3, "blocks": [{"id": "b1", "type": "embed", "object_id": 8}]}
    )
    text = document_to_agent_text(original, objects_by_id=objects)
    assert 'chartType="bar"' in text
    assert "A\\tB" in text
    assert "1\\t2" in text
    assert "#111111\\t#222222" in text
    assert "[/GRAPH]" in text
    parsed = parse_agent_text(text)
    assert parsed["object_updates"][8]["type"] == "table"
    payload = parsed["object_updates"][8]["payload"]
    assert payload["chart"]["chartType"] == "bar"
    assert payload["chart"]["enabled"] is True
    assert payload["rows"][0][0]["text"] == "A"
    assert payload["rows"][1][1]["text"] == "2"
    assert payload["chart"]["colors"] == ["#111111", "#222222"]


def test_legacy_graph_payload_still_expands():
    objects = {
        8: {
            "type": "table",
            "payload": {
                "labels": ["A", "B"],
                "values": ["1", "2"],
                "chartType": "line",
                "colors": ["#111111", "#222222"],
            },
        }
    }
    original = serialize_document(
        {"version": 3, "blocks": [{"id": "b1", "type": "embed", "object_id": 8}]}
    )
    text = document_to_agent_text(original, objects_by_id=objects)
    assert 'chartType="line"' in text
    assert "A\\tB" in text


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


def test_image_width_round_trip():
    objects = {
        5: {
            "type": "image",
            "payload": {"caption": "Shot", "url": "/uploads/a.png", "width": 0.5},
        }
    }
    original = serialize_document(
        {"version": 3, "blocks": [{"id": "b1", "type": "embed", "object_id": 5}]}
    )
    text = document_to_agent_text(original, objects_by_id=objects)
    assert 'width="0.5"' in text
    parsed = parse_agent_text(text)
    assert parsed["object_updates"][5]["payload"]["width"] == 0.5


def test_image_row_extra_panes_round_trip():
    objects = {
        5: {
            "type": "image",
            "payload": {
                "url": "/uploads/a.png",
                "caption": "A",
                "width": 0.5,
                "images": [
                    {"url": "/uploads/a.png", "caption": "A"},
                    {"url": "/uploads/b.png", "caption": "B"},
                ],
            },
        }
    }
    original = serialize_document(
        {"version": 3, "blocks": [{"id": "b1", "type": "embed", "object_id": 5}]}
    )
    text = document_to_agent_text(original, objects_by_id=objects)
    assert 'url="/uploads/a.png"' in text
    assert 'url="/uploads/b.png"' in text
    assert "[/IMAGE]" in text
    parsed = parse_agent_text(text)
    payload = parsed["object_updates"][5]["payload"]
    assert payload["url"] == "/uploads/a.png"
    assert payload["images"][1]["url"] == "/uploads/b.png"
    assert payload["images"][1]["caption"] == "B"


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


@patch("areas.production_agent.services.write_tools.purge_unreferenced_embeds_for_file")
@patch("areas.production_agent.services.write_tools.promote_legacy_embeds")
@patch("areas.production_agent.services.write_tools.apply_object_updates", return_value=[])
@patch("areas.production_agent.services.write_tools.save_file_version")
@patch("areas.production_agent.services.write_tools.db.session")
@patch("areas.production_agent.services.write_tools.ObjectEmbed")
def test_apply_document_text_direct_apply(
    mock_embed_model,
    mock_session,
    mock_save_version,
    mock_apply_objects,
    mock_promote,
    mock_purge,
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
    mock_promote.assert_called()
    mock_purge.assert_called_once()


@patch("areas.production_agent.services.write_tools.promote_legacy_embeds")
@patch("areas.production_agent.services.write_tools.db.session")
@patch("areas.production_agent.services.write_tools.ObjectEmbed")
def test_apply_document_text_review_returns_agent_text_diff(
    mock_embed_model, mock_session, mock_promote
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
    assert "object_updates" in result
    mock_promote.assert_called()

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


def _v4_body(*parts: str) -> str:
    from areas.files.services import document_marker_text as marker_text

    return marker_text.wrap_editor_text("\n\n".join(parts))


def test_v4_pointer_round_trip_info_and_tasks():
    from areas.files.services import document_marker_text as marker_text

    body = _v4_body("Intro", '[INFO id="7"]', '[TASK_LIST id="42"]')
    objects = {
        7: {
            "type": "info",
            "information": {"title": "Tip", "body": "Details"},
        },
        42: {
            "type": "task_list",
            "tasks": [
                {"title": "Call clinic", "status": "active", "list_order_index": 0},
            ],
        },
    }
    agent = document_to_agent_text(body, objects_by_id=objects)
    assert '[INFO id="7"]' in agent
    assert "Tip" in agent
    assert '[TASK_LIST id="42"]' in agent
    assert "- [ ] Call clinic" in agent

    new_body, updates, errors = apply_agent_text_to_file(
        1,
        body,
        agent.replace("Call clinic", "Call doctor"),
        known_object_ids={7, 42},
    )
    assert not errors
    assert new_body is not None
    assert marker_text.is_editor_text(new_body)
    assert '[INFO id="7"]' in new_body
    assert '[TASK_LIST id="42"]' in new_body
    assert updates[42]["tasks"][0]["title"] == "Call doctor"


def test_v4_table_pointer_round_trip():
    body = _v4_body('[TABLE id="9"]')
    objects = {
        9: {
            "type": "table",
            "payload": {"rows": [[{"text": "A"}, {"text": "B"}]]},
        }
    }
    agent = document_to_agent_text(body, objects_by_id=objects)
    assert '[TABLE id="9"]' in agent
    assert "A\\tB" in agent

    new_agent = agent.replace("A\\tB", "Alpha\\tB")
    new_body, updates, errors = apply_agent_text_to_file(
        1,
        body,
        new_agent,
        known_object_ids={9},
    )
    assert not errors
    assert '[TABLE id="9"]' in (new_body or "")
    assert updates[9]["payload"]["rows"][0][0]["text"] == "Alpha"


def test_idless_table_rejected_on_apply():
    agent = "[TABLE]\nA\tB\n[/TABLE]"
    _, _, errors = apply_agent_text_to_file(
        1,
        _v4_body(),
        agent,
        known_object_ids=set(),
    )
    assert errors
    assert any("id=" in e for e in errors)


@patch("areas.production_agent.services.write_tools.purge_unreferenced_embeds_for_file")
@patch("areas.production_agent.services.write_tools.promote_legacy_embeds")
@patch(
    "areas.production_agent.services.write_tools.apply_object_updates", return_value=[]
)
@patch("areas.production_agent.services.write_tools.db.session")
@patch("areas.production_agent.services.write_tools.ObjectEmbed")
def test_apply_document_text_review_includes_object_updates(
    mock_embed_model,
    mock_session,
    mock_apply_objects,
    mock_promote,
    mock_purge,
):
    file_row = MagicMock()
    file_row.id = 1
    file_row.topic_id = 1
    file_row.archived_at = None
    file_row.document_json = _v4_body('[INFO id="3"]')
    mock_session.get.return_value = file_row
    mock_embed = MagicMock()
    mock_embed.id = 3
    mock_embed_model.query.filter_by.return_value.all.return_value = [mock_embed]

    agent = '[INFO id="3"]\nNew title\nNew body\n[/INFO]'
    result = apply_document_text(
        1,
        agent,
        scope={"file_ids": [1]},
        write_mode="review",
        tool_name="patch_file",
    )
    assert result.get("applied") is False
    assert "object_updates" in result
    assert result["object_updates"]["3"]["title"] == "New title"
    mock_apply_objects.assert_not_called()
    mock_purge.assert_not_called()