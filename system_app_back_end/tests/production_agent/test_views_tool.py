"""Tests for the production agent views tool."""

from unittest.mock import MagicMock, patch

from areas.production_agent.services.views_tool import (
    _canonical_section,
    layout_sections,
    views_tool,
)


def test_layout_sections_skips_blank_and_sorts():
    sections = layout_sections(
        {
            "sections": [
                {"name": "Later", "order": 1},
                {"name": "  "},
                {"name": "Focus", "order": 0, "flag": "important"},
            ]
        }
    )
    assert [s["name"] for s in sections] == ["Focus", "Later"]
    assert sections[0]["flag"] == "important"


def test_canonical_section_empty_and_uncategorized():
    view = MagicMock()
    view.layout_config = {"sections": [{"name": "Focus", "order": 0}]}
    assert _canonical_section(view, None) == (None, None)
    assert _canonical_section(view, "uncategorized") == (None, None)
    name, err = _canonical_section(view, "focus")
    assert name == "Focus"
    assert err is None
    _, err = _canonical_section(view, "Nope")
    assert err is not None
    assert "unknown section" in err["error"]


def test_views_rejects_unknown_action():
    result = views_tool(
        workspace_id=1,
        action="move",
        write_mode="direct_apply",
    )
    assert result["error"].startswith("action must be")


@patch("areas.production_agent.services.views_tool.active_query")
def test_list_views_returns_sections(mock_active):
    view = MagicMock()
    view.id = 3
    view.name = "Week"
    view.layout_config = {"sections": [{"name": "Focus", "order": 0}]}
    query = MagicMock()
    query.filter_by.return_value.order_by.return_value.all.return_value = [view]
    mock_active.return_value = query

    result = views_tool(workspace_id=1, action="list", write_mode="direct_apply")
    assert result["action"] == "list"
    assert result["views"] == [
        {"view_id": 3, "name": "Week", "sections": [{"name": "Focus", "order": 0}]}
    ]
    assert "section_name" in result["uncategorized"]
