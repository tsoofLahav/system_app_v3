from areas.objects.services.table_payload import (
    chart_enabled,
    empty_chart_table_payload,
    normalize_table_payload,
    rows_to_labels_values,
)


def test_normalize_legacy_graph_shape():
    payload = normalize_table_payload(
        {
            "labels": ["A", "B"],
            "values": ["1", "2"],
            "chartType": "bar",
            "colors": ["#111", "#222"],
        }
    )
    assert chart_enabled(payload)
    assert payload["chart"]["chartType"] == "bar"
    assert payload["rows"][0][0]["text"] == "A"
    assert payload["rows"][1][1]["text"] == "2"
    labels, values = rows_to_labels_values(payload)
    assert labels == ["A", "B"]
    assert values == ["1", "2"]


def test_empty_chart_defaults():
    payload = empty_chart_table_payload()
    assert chart_enabled(payload)
    assert len(payload["rows"]) == 2
    assert payload["rows"][0][0]["text"] == ""
    assert payload["rows"][1][1]["text"] == ""


def test_plain_rows_not_chart():
    payload = normalize_table_payload(
        {"rows": [[{"text": "H1"}, {"text": "H2"}]]}
    )
    assert not chart_enabled(payload)
