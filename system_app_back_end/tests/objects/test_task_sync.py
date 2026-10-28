import pytest
from flask import Flask
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.ext.compiler import compiles
from sqlalchemy.orm import Session
from sqlalchemy.orm.exc import StaleDataError
from models import (db, Workspace, Topic, File, ObjectEmbed, InformationPiece,
                    TaskList, Task, View, ViewTaskMembership, Tag, EntityTag, Link)
from areas.objects.routes.tasks import tasks_bp
from areas.objects.routes.task_lists import task_lists_bp
from areas.objects.routes.views import views_bp
from shared.helpers import register_error_handlers


@compiles(JSONB, 'sqlite')
def jsonb_sqlite(element, compiler, **kw):
    return 'JSON'


@pytest.fixture
def client():
    app = Flask(__name__)
    app.config.update(TESTING=True, SQLALCHEMY_DATABASE_URI='sqlite://')
    db.init_app(app)
    for bp in (tasks_bp, task_lists_bp, views_bp):
        app.register_blueprint(bp)
    register_error_handlers(app)
    with app.app_context():
        for model in (Workspace, Topic, File, InformationPiece, TaskList,
                      ObjectEmbed, Task, View, ViewTaskMembership, Tag, EntityTag, Link):
            model.__table__.create(db.engine)
        db.session.add_all([Workspace(id=1, name='Test'), TaskList(id=1, title='Tasks'),
            View(id=1, workspace_id=1, name='Daily'),
            Task(id=1, task_list_id=1, title='One', status='active', list_order_index=0),
            Task(id=2, task_list_id=1, title='Two', status='done', list_order_index=1),
            ViewTaskMembership(view_id=1, task_id=1, order_index=0, topic_order_index=1),
            ViewTaskMembership(view_id=1, task_id=2, order_index=1, topic_order_index=0)])
        db.session.commit()
        yield app.test_client()
        db.session.remove()


def test_task_revision_rejects_stale_patch_without_overwrite(client):
    result = client.patch('/tasks/1', json={'title': 'New', 'base_revision': 1})
    assert result.status_code == 200
    assert result.json['revision'] == 2
    stale = client.patch('/tasks/1', json={'title': 'Old draft', 'base_revision': 1})
    assert stale.status_code == 409
    assert stale.json['task']['title'] == 'New'
    assert client.get('/tasks/1').json['title'] == 'New'


def test_orm_updates_from_other_paths_also_check_revision(client):
    with Session(db.engine) as first, Session(db.engine) as second:
        a, b = first.get(Task, 1), second.get(Task, 1)
        a.title = 'Agent edit'
        first.commit()
        b.title = 'Stale automation edit'
        with pytest.raises(StaleDataError):
            second.commit()


def test_order_compare_and_swap_rejects_stale_sequence(client):
    result = client.put('/task-lists/1/tasks/order', json={
        'ordered_task_ids': [2, 1], 'base_order': [1, 2]})
    assert result.status_code == 200
    stale = client.put('/task-lists/1/tasks/order', json={
        'ordered_task_ids': [1, 2], 'base_order': [1, 2]})
    assert stale.status_code == 409
    assert [t['id'] for t in client.get('/task-lists/1/tasks').json] == [2, 1]


def test_membership_patch_preserves_other_order_and_rejects_conflict(client):
    result = client.patch('/views/1/memberships', json={'changes': [
        {'task_id': 1, 'base': {'order_index': 0}, 'patch': {'order_index': 1}},
        {'task_id': 2, 'base': {'order_index': 1}, 'patch': {'order_index': 0}}]})
    assert result.status_code == 200
    assert {r['task_id']: r['topic_order_index'] for r in result.json} == {1: 1, 2: 0}
    stale = client.patch('/views/1/memberships', json={'changes': [
        {'task_id': 1, 'base': {'order_index': 0}, 'patch': {'order_index': 9}}]})
    assert stale.status_code == 409
    assert db.session.query(ViewTaskMembership).filter_by(task_id=1).one().order_index == 1


def test_create_retry_returns_same_task(client):
    payload = {'title': 'New task', 'creation_key': 'stable-client-row-123'}
    first = client.post('/task-lists/1/tasks', json=payload)
    second = client.post('/task-lists/1/tasks', json=payload)
    assert first.status_code == 201
    assert second.status_code == 200
    assert first.json['id'] == second.json['id']
    assert Task.query.filter_by(title='New task').count() == 1


def test_view_create_retry_does_not_duplicate_membership(client):
    payload = {'title': 'View task', 'creation_key': 'same-row'}
    first = client.post('/views/1/tasks', json=payload)
    second = client.post('/views/1/tasks', json=payload)
    assert first.status_code == 201
    assert second.status_code == 200
    assert first.json['id'] == second.json['id']
    assert ViewTaskMembership.query.filter_by(task_id=first.json['id']).count() == 1
