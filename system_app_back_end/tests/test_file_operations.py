"""Tests for duplicate and manual file move helpers."""

from types import SimpleNamespace

import pytest

from models import File, Topic
from services.duplicate_file import _copy_name, duplicate_file
from services.file_move import move_file_to_topic


def test_copy_name_adds_suffix():
    assert _copy_name("Plan", {"Plan"}) == "Plan (copy)"


def test_copy_name_increments_when_taken():
    assert _copy_name("Plan", {"Plan", "Plan (copy)"}) == "Plan (copy 2)"


def test_move_file_to_topic_rejects_missing_file(monkeypatch):
    monkeypatch.setattr("services.file_move.db.session.get", lambda _model, _id: None)
    with pytest.raises(ValueError, match="File not found"):
        move_file_to_topic(1, 2)


def test_move_file_to_topic_rejects_same_topic(monkeypatch):
    file = SimpleNamespace(
        id=1,
        archived_at=None,
        topic_id=10,
        is_main=True,
        order_index=0,
    )
    topic = SimpleNamespace(id=10, archived_at=None)

    def _get(model, obj_id):
        if model is File:
            return file
        if model is Topic:
            return topic
        return None

    monkeypatch.setattr("services.file_move.db.session.get", _get)
    with pytest.raises(ValueError, match="already in this topic"):
        move_file_to_topic(1, 10)


def test_duplicate_file_rejects_archived(monkeypatch):
    file = SimpleNamespace(id=1, archived_at="2026-01-01", topic_id=1, name="Plan")
    monkeypatch.setattr(
        "services.duplicate_file.db.session.get",
        lambda _model, _id: file,
    )
    with pytest.raises(ValueError, match="archived"):
        duplicate_file(1)
