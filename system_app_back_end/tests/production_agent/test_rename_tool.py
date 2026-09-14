from datetime import datetime
import pytest
from flask import Flask
from sqlalchemy.ext.compiler import compiles
from sqlalchemy.dialects.postgresql import JSONB
from models import db, Workspace, Topic, File, TopicType, View, Automation
from areas.production_agent.services.rename_tool import rename_tool


@compiles(JSONB, "sqlite")
def jsonb_sqlite(type_, compiler, **kw):
    return "JSON"


@pytest.fixture
def database():
    app = Flask(__name__)
    app.config.update(SQLALCHEMY_DATABASE_URI="sqlite://", TESTING=True)
    db.init_app(app)
    with app.app_context():
        db.create_all()
        db.session.add(Workspace(id=1, name="Personal"))
        db.session.add(Topic(id=1, workspace_id=1, name="Projects"))
        db.session.add(Topic(id=2, workspace_id=1, name="System", is_system=True))
        db.session.add(Workspace(id=2, name="Other"))
        db.session.add(Topic(id=3, workspace_id=2, name="Outside"))
        db.session.add(File(id=10, topic_id=1, name="Notes", document_json="{}"))
        db.session.add(TopicType(id=1, workspace_id=1, name="Project", name_he="פרויקט"))
        db.session.add(View(id=1, workspace_id=1, name="Weekly", layout_config={
            "sections": [{"key": "focus", "name": "Focus"}],
        }))
        db.session.add(Automation(
            id=1, workspace_id=1, name="Weekly / Focus", name_he="Weekly / Focus",
            kind="section_window", view_id=1, section_key="focus",
        ))
        db.session.add(View(id=2, workspace_id=2, name="Outside view"))
        db.session.commit()
        yield
        db.session.remove()
        db.drop_all()


def _call(**overrides):
    args = dict(
        workspace_id=1,
        target="topic",
        topic_id=None,
        file_id=None,
        view_id=None,
        name="",
        topic_type="",
        write_mode="direct_apply",
    )
    args.update(overrides)
    return rename_tool(**args)


def test_rename_topic(database):
    result = _call(target="topic", topic_id=1, name="  Q3 Planning  ")
    assert result["applied"] is True
    assert db.session.get(Topic, 1).name == "Q3 Planning"


def test_rename_topic_rejects_system_topic(database):
    result = _call(target="topic", topic_id=2, name="Hacked")
    assert "error" in result
    assert db.session.get(Topic, 2).name == "System"


def test_rename_topic_rejects_out_of_workspace(database):
    result = _call(target="topic", topic_id=3, name="Hacked")
    assert result["error"] == "topic not found"
    assert db.session.get(Topic, 3).name == "Outside"


def test_rename_file(database):
    result = _call(target="file", file_id=10, name="Meeting notes")
    assert result["applied"] is True
    assert db.session.get(File, 10).name == "Meeting notes"


def test_review_mode_does_not_apply(database):
    result = _call(target="topic", topic_id=1, name="Q3 Planning", write_mode="review")
    assert result["applied"] is False
    assert db.session.get(Topic, 1).name == "Projects"


def test_rename_view(database):
    result = _call(target="view", view_id=1, name="Weekly Focus")
    assert result["applied"] is True
    assert db.session.get(View, 1).name == "Weekly Focus"


def test_rename_view_resyncs_section_window_labels(database):
    _call(target="view", view_id=1, name="Weekly Focus")
    automation = db.session.get(Automation, 1)
    assert automation.name == "Weekly Focus / Focus"
    assert automation.name_he == "Weekly Focus / Focus"


def test_rename_view_rejects_out_of_workspace(database):
    result = _call(target="view", view_id=2, name="Hacked")
    assert result["error"] == "view not found"
    assert db.session.get(View, 2).name == "Outside view"


def test_rename_view_requires_name(database):
    result = _call(target="view", view_id=1, name="   ")
    assert "error" in result
    assert db.session.get(View, 1).name == "Weekly"


def test_set_topic_type_by_name_case_insensitive(database):
    result = _call(target="topic_type", topic_id=1, topic_type="project")
    assert result["applied"] is True
    assert db.session.get(Topic, 1).topic_type_id == 1


def test_set_topic_type_unknown_name_lists_existing(database):
    result = _call(target="topic_type", topic_id=1, topic_type="Nope")
    assert "error" in result
    assert "Project" in result["error"]
    assert db.session.get(Topic, 1).topic_type_id is None


def test_clear_topic_type(database):
    topic = db.session.get(Topic, 1)
    topic.topic_type_id = 1
    db.session.commit()
    result = _call(target="topic_type", topic_id=1, topic_type="")
    assert result["applied"] is True
    assert db.session.get(Topic, 1).topic_type_id is None
