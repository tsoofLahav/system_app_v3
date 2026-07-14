"""Tests for doc journey row normalization."""

def _normalize_rows(raw_rows, *, default_date="2026-07-14"):
    rows = []
    for row in raw_rows or []:
        if not isinstance(row, dict):
            continue
        text = (row.get("text") or "").strip()
        if not text:
            continue
        rows.append(
            {
                "date": (row.get("date") or default_date).strip(),
                "text": text,
            }
        )
    return rows


def test_normalize_rows_skips_empty_text():
    rows = _normalize_rows(
        [
            {"date": "2026-07-14", "text": "  shipped auth  "},
            {"date": "2026-07-14", "text": "   "},
            "bad",
        ]
    )

    assert rows == [{"date": "2026-07-14", "text": "shipped auth"}]


def test_normalize_rows_uses_default_date():
    rows = _normalize_rows([{"text": "note"}], default_date="2026-07-01")

    assert rows == [{"date": "2026-07-01", "text": "note"}]
