"""Build graph block content from AI-extracted chart data."""

from __future__ import annotations

_ALLOWED_CHART_TYPES = {"bar", "line", "pie"}


def build_graph_content(spec: dict) -> dict:
    labels = [str(item).strip() for item in (spec.get("labels") or []) if str(item).strip()]
    values: list[float] = []
    for item in spec.get("values") or []:
        if isinstance(item, (int, float)):
            values.append(float(item))
        else:
            parsed = float(str(item).strip())
            values.append(parsed)

    if not labels:
        raise ValueError("Graph must have at least one label")
    if len(labels) != len(values):
        raise ValueError("Graph labels and values must have the same length")

    chart_type = str(spec.get("chart_type") or "bar").strip().lower()
    if chart_type not in _ALLOWED_CHART_TYPES:
        chart_type = "bar"

    return {
        "chart_type": chart_type,
        "title": str(spec.get("title") or "").strip(),
        "labels": labels,
        "values": values,
        "palette_index": 0,
    }


def parse_graph_ai_result(result: dict) -> tuple[bool, str, dict | None]:
    can_graph = bool(result.get("can_graph"))
    message = str(result.get("message") or "").strip()

    if not can_graph:
        if not message:
            message = "This text does not look like data that can be turned into a graph."
        return False, message, None

    content = build_graph_content(result)
    if not message:
        message = content.get("title") or "Graph created"
    return True, message, content
