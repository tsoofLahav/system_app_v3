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
