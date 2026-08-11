"""Canonical table object payload: rows grid + optional chart quality."""

from __future__ import annotations

from typing import Any


def _cell(text: str = "") -> dict[str, Any]:
    return {"text": str(text), "spans": []}


def empty_table_payload(*, columns: int = 2) -> dict[str, Any]:
    return {
        "rows": [[_cell() for _ in range(columns)]],
    }


def empty_chart_table_payload(*, hebrew_labels: bool = False) -> dict[str, Any]:
    """Default chart table. FE insert passes labels; hebrew_labels → א/ב."""
    labels = ("א", "ב") if hebrew_labels else ("A", "B")
    return {
        "rows": [
            [_cell(labels[0]), _cell(labels[1])],
            [_cell("1"), _cell("2")],
        ],
        "chart": {
            "enabled": True,
            "chartType": "bar",
            "colors": ["#37899E", "#58C4D8"],
        },
    }


def chart_enabled(payload: dict[str, Any] | None) -> bool:
    if not payload:
        return False
    chart = payload.get("chart")
    if isinstance(chart, dict):
        return bool(chart.get("enabled"))
    # Legacy graph shape still has labels/values.
    return "labels" in payload or "values" in payload


def normalize_table_payload(payload: dict[str, Any] | None) -> dict[str, Any]:
    """Accept rows, or legacy labels/values graph shape → rows + chart."""
    raw = dict(payload or {})
    if "rows" in raw and isinstance(raw.get("rows"), list):
        rows = _normalize_rows(raw["rows"])
        out: dict[str, Any] = {"rows": rows}
        chart = raw.get("chart")
        if isinstance(chart, dict):
            out["chart"] = _normalize_chart(chart, column_count=len(rows[0]) if rows else 2)
        return out

    labels = [str(x) for x in (raw.get("labels") or [])]
    values = [str(x) for x in (raw.get("values") or [])]
    colors_raw = raw.get("colors")
    if not colors_raw and raw.get("color"):
        colors_raw = [raw.get("color")]
    colors = [str(x) for x in (colors_raw or [])] if colors_raw else []
    chart_type = str(raw.get("chartType") or raw.get("chart_type") or "bar").strip() or "bar"

    n = max(len(labels), len(values), len(colors), 2)
    labels = (labels + [""] * n)[:n]
    values = (values + [""] * n)[:n]
    colors = (colors + [""] * n)[:n] if colors else []

    return {
        "rows": [
            [_cell(t) for t in labels],
            [_cell(t) for t in values],
        ],
        "chart": {
            "enabled": True,
            "chartType": chart_type,
            "colors": colors,
        },
    }


def _normalize_rows(rows: list) -> list[list[dict[str, Any]]]:
    parsed: list[list[dict[str, Any]]] = []
    for row in rows:
        if not isinstance(row, list):
            continue
        parsed.append(
            [
                _cell(str(cell.get("text") if isinstance(cell, dict) else cell or ""))
                for cell in row
            ]
        )
    if not parsed:
        return [[_cell(), _cell()]]
    max_cols = max(len(r) for r in parsed)
    if max_cols < 1:
        max_cols = 2
    return [
        (row + [_cell()] * (max_cols - len(row)))[:max_cols]
        for row in parsed
    ]


def _normalize_chart(chart: dict[str, Any], *, column_count: int) -> dict[str, Any]:
    colors = chart.get("colors") or []
    if not isinstance(colors, list):
        colors = []
    colors = [str(c) for c in colors]
    return {
        "enabled": bool(chart.get("enabled", True)),
        "chartType": str(chart.get("chartType") or chart.get("chart_type") or "bar").strip()
        or "bar",
        "colors": colors,
    }


def rows_to_labels_values(payload: dict[str, Any]) -> tuple[list[str], list[str]]:
    """Agent GRAPH fence: first two rows as labels/values."""
    rows = payload.get("rows") or []
    if not rows:
        return [""], [""]
    labels = [
        str(c.get("text") if isinstance(c, dict) else c or "")
        for c in (rows[0] if isinstance(rows[0], list) else [])
    ]
    values = (
        [
            str(c.get("text") if isinstance(c, dict) else c or "")
            for c in (rows[1] if len(rows) > 1 and isinstance(rows[1], list) else [])
        ]
        if len(rows) > 1
        else [""] * len(labels)
    )
    n = max(len(labels), len(values), 1)
    labels = (labels + [""] * n)[:n]
    values = (values + [""] * n)[:n]
    return labels, values


def chart_meta(payload: dict[str, Any]) -> dict[str, Any]:
    chart = payload.get("chart") if isinstance(payload.get("chart"), dict) else {}
    colors = chart.get("colors") or []
    if not isinstance(colors, list):
        colors = []
    return {
        "chartType": str(chart.get("chartType") or "bar"),
        "colors": [str(c) for c in colors],
    }
