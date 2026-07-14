"""Tests for topic duplication helpers."""

from services.duplicate_topic import _remap_block_content


def test_remap_block_content_updates_part_id():
    content = _remap_block_content(
        {"text": "Auth", "level": 2, "part_id": 3},
        {3: 99},
    )

    assert content["part_id"] == 99
    assert content["text"] == "Auth"


def test_remap_block_content_leaves_unknown_part_id():
    content = _remap_block_content({"part_id": 5}, {3: 99})

    assert content["part_id"] == 5
