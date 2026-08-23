"""Guards for persisted objects-map coordinates."""

import inspect

from areas.objects.routes import objects as object_routes
from areas.objects.services import object_graph
from models import ObjectEmbed


def test_object_has_diagram_columns():
    columns = {c.name for c in ObjectEmbed.__table__.columns}
    assert {"diagram_x", "diagram_y"} <= columns
    source = inspect.getsource(ObjectEmbed.to_dict)
    assert "diagram_x" in source
    assert "diagram_y" in source


def test_graph_payload_includes_positions():
    source = inspect.getsource(object_graph.build_workspace_graph)
    assert "diagram_x" in source
    assert "diagram_y" in source


def test_position_routes_exist():
    source = inspect.getsource(object_routes)
    assert '"/objects/graph/positions"' in source
    assert "apply_diagram_positions" in source
    assert "diagram_x" in inspect.getsource(object_routes.update_object)


def test_apply_diagram_positions_skips_unknown_ids():
    class FakeEmbed:
        def __init__(self, id_):
            self.id = id_
            self.diagram_x = None
            self.diagram_y = None

    kept = FakeEmbed(7)

    def fake_workspace_ids(_workspace_id):
        return [kept]

    original = object_graph.workspace_object_ids
    object_graph.workspace_object_ids = fake_workspace_ids
    try:
        updated = object_graph.apply_diagram_positions(
            1,
            [
                {"object_id": 7, "x": 12.5, "y": -4},
                {"object_id": 99, "x": 1, "y": 1},
                {"object_id": 7, "x": None, "y": 3},
            ],
        )
    finally:
        object_graph.workspace_object_ids = original

    assert updated == 1
    assert kept.diagram_x == 12.5
    assert kept.diagram_y == -4
