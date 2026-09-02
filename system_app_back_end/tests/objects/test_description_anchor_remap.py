"""Description-link offset remap (same rules as the file editor)."""

from areas.objects.services.description_anchor_remap import (
    remap_offset_range,
    remap_table_description_links,
)


def test_typing_before_a_connected_span_moves_the_underline():
    old_text = "call the clinic"
    new_text = "please call the clinic"
    next_range = remap_offset_range(0, 15, old_text, new_text)
    assert next_range is not None
    start, end = next_range
    assert new_text[start:end] == "call the clinic"


def test_typing_immediately_before_the_span_does_not_eat_new_characters():
    old_text = "clinic"
    new_text = "the clinic"
    next_range = remap_offset_range(0, 6, old_text, new_text)
    assert next_range is not None
    start, end = next_range
    assert new_text[start:end] == "clinic"


def test_insert_inside_the_span_grows_the_underline():
    old_text = "call clinic"
    new_text = "call the clinic"
    next_range = remap_offset_range(0, 11, old_text, new_text)
    assert next_range is not None
    start, end = next_range
    assert new_text[start:end] == "call the clinic"


def test_deleting_the_connected_glyphs_drops_the_range():
    next_range = remap_offset_range(3, 9, "xx clinic yy", "xx  yy")
    assert next_range is None


def test_remap_description_links_for_text_shifts_task_title(monkeypatch):
    from areas.objects.services import description_anchor_remap as remap
    from areas.objects.services.description_anchor_remap import (
        remap_description_links_for_text,
    )

    class FakeLink:
        def __init__(self):
            self.kind = "description"
            self.anchor = {
                "segment_id": "task:11",
                "start": 0,
                "end": 15,
            }
            self.patched = None

    link = FakeLink()

    class _Query:
        def filter(self, *args, **kwargs):
            return self

        def all(self):
            return [link]

    class FakeLinkModel:
        query = _Query()
        kind = object()
        source_type = object()
        source_id = object()
        target_type = object()

    monkeypatch.setattr(remap, "Link", FakeLinkModel)
    monkeypatch.setattr(
        remap, "patch_description_anchor", lambda row, raw: setattr(row, "patched", raw)
    )

    remap_description_links_for_text(
        source_type="task",
        source_id=11,
        old_text="call the clinic",
        new_text="please call the clinic",
        segment_id="task:11",
    )
    assert link.patched["start"] == 7
    assert link.patched["end"] == 22


def test_remap_table_description_links_shifts_cell_span(monkeypatch):
    from areas.objects.services import description_anchor_remap as remap

    class FakeLink:
        def __init__(self):
            self.kind = "description"
            self.anchor = {
                "segment_id": "embed:9#c0:0",
                "start": 0,
                "end": 6,
            }
            self.patched = None

        def to_dict(self):
            return self.anchor

    link = FakeLink()

    class _Query:
        def filter(self, *args, **kwargs):
            return self

        def all(self):
            return [link]

    class FakeLinkModel:
        query = _Query()
        kind = type("Col", (), {})()
        source_id = type("Col", (), {})()
        target_type = type("Col", (), {})()

    monkeypatch.setattr(remap, "Link", FakeLinkModel)

    def fake_patch(row, raw):
        row.patched = raw
        return raw

    monkeypatch.setattr(remap, "patch_description_anchor", fake_patch)

    remap_table_description_links(
        9,
        {"rows": [[{"text": "clinic"}]]},
        {"rows": [[{"text": "the clinic"}]]},
    )
    assert link.patched["start"] == 4
    assert link.patched["end"] == 10
