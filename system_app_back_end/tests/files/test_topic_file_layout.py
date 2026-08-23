"""Guards that prominence lives on the topic's layout, not on a flag per file.

Which files a topic shows is derived from ``topics.file_layout`` plus
``files.order_index``. Reintroducing a per-file flag would give the app two
sources for the same answer, and they would disagree.

The app needs Postgres (JSONB columns), so these inspect the model and route
source rather than calling the routes.
"""

import inspect

from areas.files.routes import topics as topics_routes
from models import File, Topic

LAYOUT_IDS = {"auto", "single", "split", "hero_left", "hero_right", "row", "grid"}


def test_topic_stores_its_file_layout():
    column = Topic.__table__.columns["file_layout"]
    assert not column.nullable
    assert column.default.arg == "auto"


def test_topic_serializes_its_file_layout():
    assert "file_layout" in inspect.getsource(Topic.to_dict)


def test_layout_is_updatable_through_the_api():
    source = inspect.getsource(topics_routes.update_topic)
    assert '"file_layout"' in source, (
        "PATCH /topics/<id> must accept file_layout — it is the only way the "
        "arrange dialog persists which files stay on screen"
    )


def test_file_has_no_prominence_flag():
    assert "is_essence" not in File.__table__.columns, (
        "Prominence comes from the topic layout and order_index; a flag on the "
        "file would be a second, conflicting source of truth"
    )


def test_file_is_not_serialized_with_a_prominence_flag():
    assert "is_essence" not in inspect.getsource(File.to_dict)
