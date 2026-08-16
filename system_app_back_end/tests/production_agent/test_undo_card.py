"""Unit tests for compact undo card on direct_apply."""

from areas.production_agent.services.write_tools import build_undo_card


class _FakeTopic:
    def __init__(self, name: str):
        self.name = name


class _FakeFile:
    def __init__(self, *, file_id: int, name: str, topic_id: int):
        self.id = file_id
        self.name = name
        self.topic_id = topic_id


def test_build_undo_card_add_preview(monkeypatch):
    from areas.production_agent.services import write_tools as wt

    monkeypatch.setattr(
        wt,
        "load_objects_by_id",
        lambda _fid: {},
    )
    monkeypatch.setattr(
        wt,
        "document_to_agent_text",
        lambda doc, objects_by_id=None: doc,
    )
    monkeypatch.setattr(
        wt.db.session,
        "get",
        lambda model, tid: _FakeTopic("Health") if tid == 2 else None,
    )

    file = _FakeFile(file_id=1, name="Notes", topic_id=2)
    card = build_undo_card(
        file=file,
        old_document_json="a\nb\n",
        new_agent_text="a\nb\nc\n",
    )
    assert card["file_name"] == "Notes"
    assert card["topic_name"] == "Health"
    assert card["old_document_json"] == "a\nb\n"
    assert len(card["changes"]) == 1
    assert card["changes"][0]["op"] == "add"
    assert card["changes"][0]["text"] == "c"


def test_build_undo_card_change_and_remove(monkeypatch):
    from areas.production_agent.services import write_tools as wt

    monkeypatch.setattr(wt, "load_objects_by_id", lambda _fid: {})
    monkeypatch.setattr(
        wt,
        "document_to_agent_text",
        lambda doc, objects_by_id=None: doc,
    )
    monkeypatch.setattr(wt.db.session, "get", lambda model, tid: _FakeTopic("T"))

    file = _FakeFile(file_id=1, name="F", topic_id=1)
    change_card = build_undo_card(
        file=file,
        old_document_json="a\nb\n",
        new_agent_text="a\nB\n",
    )
    assert change_card["changes"][0]["op"] == "change"
    assert change_card["changes"][0]["text"] == "B"

    remove_card = build_undo_card(
        file=file,
        old_document_json="a\nb\n",
        new_agent_text="a\n",
    )
    assert remove_card["changes"][0]["op"] == "remove"
    assert remove_card["changes"][0]["text"] == "b"
