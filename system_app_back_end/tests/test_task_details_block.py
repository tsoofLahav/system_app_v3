"""Tests for task details_block_id validation."""

import pytest

from services.details_lookup import validate_details_block_for_topic


def test_validate_details_block_requires_details_type(monkeypatch):
    block = type("Block", (), {"type": "text", "archived_at": None, "file_id": 3})()
    file = type("File", (), {"topic_id": 1, "anchor_topic_id": None, "archived_at": None})()

    monkeypatch.setattr(
        "services.details_lookup.db.session.get",
        lambda model, item_id: block if item_id == 10 else file,
    )

    with pytest.raises(ValueError, match="details block"):
        validate_details_block_for_topic(10, topic_id=1)


def test_validate_details_block_requires_same_topic(monkeypatch):
    block = type("Block", (), {"type": "details", "archived_at": None, "file_id": 3})()
    file = type("File", (), {"topic_id": 2, "anchor_topic_id": None, "archived_at": None})()

    monkeypatch.setattr(
        "services.details_lookup.db.session.get",
        lambda model, item_id: block if item_id == 10 else file,
    )

    with pytest.raises(ValueError, match="same topic"):
        validate_details_block_for_topic(10, topic_id=1)
