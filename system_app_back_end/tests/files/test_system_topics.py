"""Built-in Reports topic — Archive only, not user-editable."""

import inspect

from areas.files.routes import files as files_routes
from areas.files.routes import topics as topics_routes
from areas.files.services import system_topics
from models import Topic


def test_topic_has_is_system():
    assert "is_system" in Topic.__table__.columns
    assert "is_system" in inspect.getsource(Topic.to_dict)


def test_ensure_reports_topic_is_system():
    source = inspect.getsource(system_topics.ensure_system_reports_topic)
    assert 'name=SYSTEM_REPORTS_TOPIC_NAME' in source or "SYSTEM_REPORTS_TOPIC_NAME" in source
    assert "is_system=True" in source
    assert "_adopt_stray_report_files" in inspect.getsource(
        system_topics.ensure_system_reports_topic
    )


def test_routes_block_system_topic_edits():
    patch = inspect.getsource(topics_routes.update_topic)
    delete = inspect.getsource(topics_routes.delete_topic)
    listing = inspect.getsource(topics_routes.list_topics)
    assert "system topics cannot be edited" in patch
    assert "system topics cannot be deleted" in delete
    assert "ensure_system_reports_topic" in listing


def test_unarchive_blocked_on_system_topic():
    source = inspect.getsource(files_routes.update_file)
    assert "system reports stay in archive" in source
