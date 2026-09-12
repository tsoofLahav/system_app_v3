import pytest
from flask import Flask
from sqlalchemy.ext.compiler import compiles
from sqlalchemy.dialects.postgresql import JSONB
from models import db, Workspace, Topic, File, ObjectEmbed, TaskList, Task
from shared.workspace_scope import register_workspace_scope
from shared.routes.workspaces import workspaces_bp
from shared.routes.bootstrap import bootstrap_bp
from areas.objects.routes.tasks import tasks_bp
from areas.files.routes.files import files_bp
from shared.helpers import register_error_handlers


@compiles(JSONB, 'sqlite')
def jsonb_sqlite(type_, compiler, **kw):
    return 'JSON'


@pytest.fixture
def app():
    app = Flask(__name__)
    app.config.update(SQLALCHEMY_DATABASE_URI='sqlite://', TESTING=True)
    db.init_app(app)
    app.register_blueprint(workspaces_bp)
    app.register_blueprint(bootstrap_bp)
    app.register_blueprint(tasks_bp)
    app.register_blueprint(files_bp)
    register_error_handlers(app)
    register_workspace_scope(app)
    with app.app_context():
        db.create_all()
        for wid in (1, 2):
            db.session.add(Workspace(id=wid, name=f'Profile {wid}'))
            db.session.add(Topic(id=wid, workspace_id=wid, name='Home'))
            db.session.add(File(id=wid, topic_id=wid, name=f'Journal {wid}', document_json=''))
            db.session.add(TaskList(id=wid, title='Tasks'))
            db.session.add(ObjectEmbed(id=wid, file_id=wid, type='task_list', task_list_id=wid))
            db.session.add(Task(id=wid, task_list_id=wid, title=f'Task {wid}'))
        db.session.commit()
    yield app
    with app.app_context():
        db.session.remove()
        db.drop_all()


def test_selected_bootstrap_does_not_fall_back(app):
    client = app.test_client()
    assert client.get('/bootstrap/status', headers={'X-Workspace-Id':'2'}).json['workspace_id'] == 2
    assert client.get('/bootstrap/status').json['workspace_id'] == 1
    assert client.get('/bootstrap/status', headers={'X-Workspace-Id':'999'}).status_code == 404


def test_profile_lists_and_id_access_are_separate(app):
    client = app.test_client()
    for wid in (1, 2, 1):
        headers = {'X-Workspace-Id': str(wid)}
        rows = client.get('/tasks', headers=headers)
        assert rows.status_code == 200, rows.json
        assert [row['id'] for row in rows.json] == [wid]
        assert client.get(f'/files/{wid}', headers=headers).status_code == 200
        assert client.get(f'/files/{3-wid}', headers=headers).status_code == 404
        assert client.patch(f'/tasks/{3-wid}', headers=headers, json={'title':'wrong'}).status_code == 404


def test_foreign_relationship_and_workspace_rejected(app):
    client = app.test_client()
    headers={'X-Workspace-Id':'2'}
    assert client.patch('/tasks/2',headers=headers,json={'task_list_id':1}).status_code == 404
    assert client.get('/tasks?workspace_id=1',headers=headers).status_code == 403


def test_create_profile_is_blank_and_preserves_existing(app):
    client = app.test_client()
    result = client.post('/workspaces',json={'name':'Demo'})
    assert result.status_code == 201, result.json
    wid = result.json['id']
    with app.app_context():
        topics = Topic.query.filter_by(workspace_id=wid).all()
        assert len(topics)==1 and topics[0].name=='Home'
        files = File.query.filter_by(topic_id=topics[0].id).all()
        assert len(files)==1 and 'Journal' not in files[0].document_json
        assert db.session.get(File,1).name=='Journal 1'
