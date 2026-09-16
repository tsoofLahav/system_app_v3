"""Home visit membership on the workspace."""

from flask import Flask
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.ext.compiler import compiles
from models import File, Topic, Workspace, db
from areas.files.services import home_visits
from areas.files.routes.topics import topics_bp


def test_home_topic_name_is_case_insensitive():
    assert home_visits.is_home_topic(Topic(name="Home", workspace_id=1))
    assert home_visits.is_home_topic(Topic(name="HOME", workspace_id=1))
    assert not home_visits.is_home_topic(Topic(name="Work", workspace_id=1))
    assert not home_visits.is_home_topic(None)


@compiles(JSONB, "sqlite")
def jsonb_sqlite(type_, compiler, **kw):
    return "JSON"


def test_translated_home_is_found_and_repaired_by_daily_anchor():
    app = Flask(__name__)
    app.config.update(SQLALCHEMY_DATABASE_URI="sqlite://", TESTING=True)
    db.init_app(app)
    app.register_blueprint(topics_bp)
    with app.app_context():
        db.create_all()
        db.session.add(Workspace(id=1, name="Personal"))
        db.session.add(Topic(id=1, workspace_id=1, name="בית", color="#6366F1"))
        db.session.add(Topic(id=2, workspace_id=1, name="Other"))
        db.session.add(File(id=1, topic_id=1, name="Journal", document_json="{}", meta={"automation_anchor": "daily"}))
        db.session.add(File(id=2, topic_id=2, name="Copied journal", document_json="{}", meta={"automation_anchor": "daily"}))
        db.session.commit()

        home = db.session.get(Topic, 1)
        assert home_visits.is_home_topic(home)
        assert not home_visits.is_home_topic(db.session.get(Topic, 2))
        response = app.test_client().get("/topics?workspace_id=1")
        assert response.status_code == 200
        db.session.expire_all()
        assert db.session.get(Topic, 1).name == "Home"
        assert db.session.get(Topic, 1).color is None
        db.session.remove()
        db.drop_all()


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
