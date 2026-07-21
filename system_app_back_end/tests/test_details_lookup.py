"""Tests for details lookup helpers."""

from services.details_lookup import (
    details_text,
    details_title,
    suggest_details_block_id,
    text_preview,
)


def test_details_title_from_content():
    assert details_title({"title": " Recipe "}) == "Recipe"
    assert details_title({}) == ""


def test_details_text_from_content():
    assert details_text({"text": " Steps "}) == "Steps"


def test_text_preview_truncates():
    long = "word " * 50
    preview = text_preview(long, limit=20)
    assert len(preview) <= 20
    assert preview.endswith("…")


def test_suggest_details_block_id_with_inline_candidates(monkeypatch):
    items = [
        {"block_id": 1, "title": "Chicken soup", "text_preview": "broth"},
        {"block_id": 2, "title": "Salad", "text_preview": "greens"},
    ]
    monkeypatch.setattr(
        "services.details_lookup.list_details_blocks_for_topic",
        lambda _topic_id: items,
    )
    assert suggest_details_block_id(topic_id=1, query="chicken soup") == 1
    assert suggest_details_block_id(topic_id=1, query="salad") == 2
