from datetime import datetime
import pytest
from flask import Flask
from sqlalchemy.ext.compiler import compiles
from sqlalchemy.dialects.postgresql import JSONB
from models import db, Workspace, Topic, File, TopicType
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
        db.session.commit()
        yield
        db.session.remove()
        db.drop_all()


def test_rename_topic(database):
    result = rename_tool(
        workspace_id=1,
        target="topic",
        topic_id=1,
        file_id=None,
        name="  Q3 Planning  ",
        topic_type="",
        write_mode="direct_apply",
    )
    assert result["applied"] is True
    assert db.session.get(Topic, 1).name == "Q3 Planning"


def test_rename_topic_rejects_system_topic(database):
    result = rename_tool(
        workspace_id=1,
        target="topic",
        topic_id=2,
        file_id=None,
        name="Hacked",
        topic_type="",
        write_mode="direct_apply",
    )
    assert "error" in result
    assert db.session.get(Topic, 2).name == "System"


def test_rename_topic_rejects_out_of_workspace(database):
    result = rename_tool(
        workspace_id=1,
        target="topic",
        topic_id=3,
        file_id=None,
        name="Hacked",
        topic_type="",
        write_mode="direct_apply",
    )
    assert result["error"] == "topic not found"
    assert db.session.get(Topic, 3).name == "Outside"


def test_rename_file(database):
    result = rename_tool(
        workspace_id=1,
        target="file",
        topic_id=None,
        file_id=10,
        name="Meeting notes",
        topic_type="",
        write_mode="direct_apply",
    )
    assert result["applied"] is True
    assert db.session.get(File, 10).name == "Meeting notes"


def test_review_mode_does_not_apply(database):
    result = rename_tool(
        workspace_id=1,
        target="topic",
        topic_id=1,
        file_id=None,
        name="Q3 Planning",
        topic_type="",
        write_mode="review",
    )
    assert result["applied"] is False
    assert db.session.get(Topic, 1).name == "Projects"


def test_set_topic_type_by_name_case_insensitive(database):
    result = rename_tool(
        workspace_id=1,
        target="topic_type",
        topic_id=1,
        file_id=None,
        name="",
        topic_type="project",
        write_mode="direct_apply",
    )
    assert result["applied"] is True
    assert db.session.get(Topic, 1).topic_type_id == 1


def test_set_topic_type_unknown_name_lists_existing(database):
    result = rename_tool(
        workspace_id=1,
        target="topic_type",
        topic_id=1,
        file_id=None,
        name="",
        topic_type="Nope",
        write_mode="direct_apply",
    )
    assert "error" in result
    assert "Project" in result["error"]
    assert db.session.get(Topic, 1).topic_type_id is None


def test_clear_topic_type(database):
    topic = db.session.get(Topic, 1)
    topic.topic_type_id = 1
    db.session.commit()
    result = rename_tool(
        workspace_id=1,
        target="topic_type",
        topic_id=1,
        file_id=None,
        name="",
        topic_type="",
        write_mode="direct_apply",
    )
    assert result["applied"] is True
    assert db.session.get(Topic, 1).topic_type_id is None
