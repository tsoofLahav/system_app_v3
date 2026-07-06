"""Tests for graph content parsing."""

import pytest

from services.ai_interactive.graph_content import build_graph_content, parse_graph_ai_result


def test_build_graph_content_from_spec():
    content = build_graph_content(
        {
            "title": "Weekly scores",
            "chart_type": "line",
            "labels": ["Mon", "Tue", "Wed"],
            "values": [3, 5, 4],
        }
    )

    assert content == {
        "chart_type": "line",
        "title": "Weekly scores",
        "labels": ["Mon", "Tue", "Wed"],
        "values": [3.0, 5.0, 4.0],
        "palette_index": 0,
    }


def test_parse_graph_ai_result_rejects_non_graphable_text():
    can_graph, message, content = parse_graph_ai_result(
        {"can_graph": False, "message": "This is a narrative paragraph."}
    )

    assert can_graph is False
    assert "narrative" in message
    assert content is None


def test_parse_graph_ai_result_accepts_graphable_text():
    can_graph, message, content = parse_graph_ai_result(
        {
            "can_graph": True,
            "message": "Created from scores",
            "title": "Scores",
            "chart_type": "bar",
            "labels": ["A", "B"],
            "values": [1, 2],
        }
    )

    assert can_graph is True
    assert message == "Created from scores"
    assert content is not None
    assert content["labels"] == ["A", "B"]


def test_build_graph_content_requires_matching_lengths():
    with pytest.raises(ValueError):
        build_graph_content(
            {
                "labels": ["A", "B"],
                "values": [1],
            }
        )
