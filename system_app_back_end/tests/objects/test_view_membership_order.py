"""Guards for GET /topics/<id>/task-lists and dual view-order columns."""

import inspect

from areas.files.routes import topics as topics_routes
from areas.objects.routes import tasks as tasks_routes
from areas.objects.routes import views as views_routes
from models import ViewTaskMembership


def test_topic_task_lists_route_exists():
    source = inspect.getsource(topics_routes)
    assert '"/topics/<int:topic_id>/task-lists"' in source
    assert "list_topic_task_lists" in source


def test_topic_task_lists_skips_archived_files():
    source = inspect.getsource(topics_routes.list_topic_task_lists)
    assert "archived_at" in source
    assert "task_list" in source


def test_membership_has_topic_order_index():
    columns = {c.name for c in ViewTaskMembership.__table__.columns}
    assert "topic_order_index" in columns
    assert "order_index" in columns
    source = inspect.getsource(ViewTaskMembership.to_dict)
    assert "topic_order_index" in source


def test_replace_memberships_writes_topic_order_index():
    assert "topic_order_index" in inspect.getsource(views_routes.replace_memberships)
    assert "topic_order_index" in inspect.getsource(
        tasks_routes.replace_task_memberships
    )
    assert "topic_order_index" in inspect.getsource(views_routes.create_view_task)


def test_topic_order_index_falls_back_to_order_index():
    assert views_routes._topic_order_index({"order_index": 4}, 0) == 4
    assert views_routes._topic_order_index({"topic_order_index": 7, "order_index": 1}, 0) == 7
    assert views_routes._topic_order_index({}, 3) == 3
