"""Home visit membership on the workspace."""

from models import Topic, Workspace
from areas.files.services import home_visits


def test_home_topic_name_is_case_insensitive():
    assert home_visits.is_home_topic(Topic(name="Home", workspace_id=1))
    assert home_visits.is_home_topic(Topic(name="HOME", workspace_id=1))
    assert not home_visits.is_home_topic(Topic(name="Work", workspace_id=1))
    assert not home_visits.is_home_topic(None)


def test_visit_ids_dedupe_and_skip_junk():
    workspace = Workspace(name="Default")
    workspace.home_visit_file_ids = [3, "3", 7, "x", None]
    assert home_visits.visit_ids_of(workspace) == [3, 7]


def test_canvas_ids_dedupe_and_skip_junk():
    workspace = Workspace(name="Default")
    workspace.home_canvas_file_ids = [1, "1", 99, "x", None]
    assert home_visits.canvas_ids_of(workspace) == [1, 99]


def test_set_canvas_ids_dedupes_and_keeps_order():
    workspace = Workspace(name="Default")
    assert home_visits.set_canvas_ids(workspace, [99, 1, 99, 2]) == [99, 1, 2]
    assert home_visits.canvas_ids_of(workspace) == [99, 1, 2]
