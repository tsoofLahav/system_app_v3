"""Tests for apply_units_to_file list block grouping."""

from types import SimpleNamespace

from services.unit_mapper import apply_units_to_file


class _FakeSession:
    def __init__(self):
        self.added = []
        self._id = 100

    def add(self, obj):
        self.added.append(obj)
        if getattr(obj, "id", None) is None:
            self._id += 1
            obj.id = self._id

    def flush(self):
        return None


def test_apply_units_to_file_splits_list_items_by_block_id(monkeypatch):
    session = _FakeSession()
    monkeypatch.setattr("services.unit_mapper.db.session", session)

    file = SimpleNamespace(id=1)
    units = [
        {"id": "h1", "kind": "header", "text": "Part A", "block_id": 1},
        {"id": "a1", "kind": "list_item", "text": "Line A1", "block_id": 10},
        {"id": "a2", "kind": "list_item", "text": "Line A2", "block_id": 10},
        {"id": "new1", "kind": "list_item", "text": "Inserted", "block_id": 10},
        {"id": "h2", "kind": "header", "text": "Part B", "block_id": 2},
        {"id": "b1", "kind": "list_item", "text": "Line B1", "block_id": 20},
    ]

    apply_units_to_file(file, units)

    list_blocks = [obj for obj in session.added if obj.type == "list"]
    assert len(list_blocks) == 2
    assert list_blocks[0].content["items"] == [
        {"text": "Line A1"},
        {"text": "Line A2"},
        {"text": "Inserted"},
    ]
    assert list_blocks[1].content["items"] == [{"text": "Line B1"}]
