"""Clones have independent storage and atomically placed pointers."""
import pytest
from flask import Flask
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.ext.compiler import compiles
from models import (db, Workspace, Topic, File, ObjectEmbed, InformationPiece,
                    TaskList, Task, View, ViewTaskMembership, Tag, EntityTag, Link)
from areas.objects.routes.objects import objects_bp
from areas.objects.services.create_embed import create_embed_in_file


@compiles(JSONB, "sqlite")
def sqlite_jsonb(element, compiler, **kw):
    return "JSON"


@pytest.fixture
def client():
    app = Flask(__name__)
    app.config.update(TESTING=True, SQLALCHEMY_DATABASE_URI="sqlite://")
    db.init_app(app)
    app.register_blueprint(objects_bp)
    with app.app_context():
        for model in (Workspace, Topic, File, InformationPiece, TaskList,
                      ObjectEmbed, Task, View, ViewTaskMembership, Tag, EntityTag, Link):
            model.__table__.create(db.engine)
        db.session.add_all([Workspace(id=1, name="Test"), Topic(id=1, workspace_id=1, name="One"),
                            Topic(id=2, workspace_id=1, name="Two"),
                            File(id=1, topic_id=1, name="Source"), File(id=2, topic_id=2, name="Destination")])
        db.session.commit()
        yield app.test_client()
        db.session.remove()


def paste(client, source_id, **overrides):
    data = {"source_object_id": source_id, "block_index": 0,
            "base_revision": db.session.get(File, 2).content_revision}
    data.update(overrides)
    return client.post('/files/2/objects/clone', json=data)


def test_info_independent_and_reads_current_source(client):
    source = create_embed_in_file(db.session.get(File, 1), type_="info", title="Title", body="☐ Task\n• Item", payload={"look": "ruled"})
    info = db.session.get(InformationPiece, source.information_id)
    info.metadata_ = {"body_spans": [{"start": 0, "end": 6, "bold": True}]}
    db.session.add(Tag(id=1, workspace_id=1, name="Tag"))
    db.session.add(EntityTag(tag_id=1, entity_type="object", entity_id=source.id))
    db.session.commit()
    original_doc = db.session.get(File, 1).document_json
    first = paste(client, source.id)
    assert first.status_code == 201
    copied = first.get_json()
    assert copied['id'] != source.id and copied['information_id'] != info.id
    assert copied['information']['body'] == info.body
    assert copied['information']['metadata'] == info.metadata_
    assert copied['payload'] == source.payload
    assert copied['tags'][0]['id'] == 1
    assert f'[INFO id="{copied["id"]}"]' in db.session.get(File, 2).document_json
    info.body = "Changed after copying pointer"
    db.session.commit()
    second = paste(client, source.id).get_json()
    assert second['id'] != copied['id']
    assert second['information']['body'] == info.body
    assert db.session.get(InformationPiece, copied['information_id']).body == "☐ Task\n• Item"
    assert db.session.get(File, 1).document_json == original_doc


@pytest.mark.parametrize('type_,payload,tag', [
    ('image', {'url': '/images/a.png', 'width': .5, 'look': 'frame'}, 'IMAGE'),
    ('table', {'rows': [[{'text': 'Hello'}]], 'look': 'lined'}, 'TABLE'),
    ('graph', {'rows': [[{'text': 'X'}], [{'text': '2'}]], 'chart': {'enabled': True, 'chartType': 'bar'}}, 'GRAPH'),
])
def test_payload_objects(client, type_, payload, tag):
    source = create_embed_in_file(db.session.get(File, 1), type_=type_, payload=payload)
    db.session.commit()
    response = paste(client, source.id)
    assert response.status_code == 201
    clone = response.get_json()
    assert clone['payload'] == source.payload
    assert f'[{tag} id="{clone["id"]}"]' in db.session.get(File, 2).document_json


def test_task_ids_styles_and_memberships(client):
    source = create_embed_in_file(db.session.get(File, 1), type_="task_list", title="Work")
    task = Task(task_list_id=source.task_list_id, title="Do it", status="active", title_spans=[{'start': 0, 'end': 2, 'bold': True}])
    db.session.add(task)
    db.session.flush()
    db.session.add(View(id=1, workspace_id=1, name="Today"))
    db.session.add(ViewTaskMembership(view_id=1, task_id=task.id, section_name="Work", order_index=3, topic_order_index=4, topic_key="topic_1"))
    db.session.commit()
    response = paste(client, source.id)
    assert response.status_code == 201
    clone = response.get_json()
    copied = clone['tasks'][0]
    assert clone['task_list_id'] != source.task_list_id
    assert clone['task_list']['title'] == "Work"
    assert copied['id'] != task.id and copied['status'] == 'active'
    assert copied['title_spans'] == task.title_spans
    membership = ViewTaskMembership.query.filter_by(task_id=copied['id']).one()
    assert (membership.view_id, membership.topic_key, membership.order_index) == (1, 'topic_2', 4)
    db.session.get(Task, copied['id']).title = 'Changed copy'
    db.session.commit()
    assert task.title == 'Do it'


def test_invalid_requests_create_nothing(client):
    source = create_embed_in_file(db.session.get(File, 1), type_='info')
    db.session.commit()
    before = ObjectEmbed.query.count()
    assert paste(client, 9999).status_code == 404
    assert paste(client, source.id, base_revision=0).status_code == 409
    assert paste(client, source.id, block_index=-1).status_code == 400
    db.session.get(Topic, 2).workspace_id = 2
    db.session.commit()
    assert paste(client, source.id).status_code == 400
    assert ObjectEmbed.query.count() == before
