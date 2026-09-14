from datetime import datetime, timedelta
from uuid import uuid4
from unittest.mock import patch
import pytest
from flask import Flask
from sqlalchemy.ext.compiler import compiles
from sqlalchemy.dialects.postgresql import JSONB
from models import db, Workspace, PushDevice
from areas.automations.services import push_notifications as push
from areas.automations.routes.push_devices import push_devices_bp
from shared.workspace_scope import register_workspace_scope

@compiles(JSONB, 'sqlite')
def jsonb_sqlite(type_, compiler, **kw):
    return 'JSON'

@pytest.fixture
def app(monkeypatch):
    app = Flask(__name__)
    app.config.update(SQLALCHEMY_DATABASE_URI='sqlite://', TESTING=True)
    db.init_app(app)
    app.register_blueprint(push_devices_bp)
    register_workspace_scope(app)
    for key in ('APNS_KEY_ID', 'APNS_TEAM_ID', 'APNS_TOPIC', 'APNS_KEY_FILE'):
        monkeypatch.setenv(key, 'test')
    monkeypatch.setenv('APNS_ENABLED', 'true')
    with app.app_context():
        db.create_all()
        db.session.add_all([Workspace(id=1, name='Personal'), Workspace(id=2, name='Demo')])
        db.session.commit()
        yield app
        db.session.remove()
        db.drop_all()


def device(wid=1):
    row = PushDevice(installation_id=str(uuid4()), workspace_id=wid, token='ab'*32,
                     environment='sandbox', language='he')
    db.session.add(row)
    db.session.commit()
    return row


def section(key='1:today'):
    return {'key': key, 'title': 'Evening', 'title_he': 'ערב'}


def test_delivery_retry_dedupe_and_badge_clear(app):
    row = device()
    sent = []
    def sender(d, p):
        sent.append(p)
        return 200, ''
    with patch.object(push, 'section_snapshot', return_value=[section()]):
        assert push.dispatch(lambda d,p: (503, 'Unavailable')) == 0
        assert row.last_badge == -1
        assert push.dispatch(sender) == 1
        assert push.dispatch(sender) == 0
    assert sent[0]['aps']['badge'] == 1
    assert sent[0]['aps']['alert']['title'] == 'ערב'
    with patch.object(push, 'section_snapshot', return_value=[]):
        assert push.dispatch(sender) == 1
        assert push.dispatch(sender) == 0
    assert sent[-1]['aps']['badge'] == 0
    assert 'alert' not in sent[-1]['aps']


def test_new_occurrence_with_same_badge_alerts(app):
    row = device()
    row.last_keys = ['1:yesterday']; row.last_badge = 1
    assert 'alert' in push.notification_payload(row, [section()])['aps']


def test_invalid_device_deactivated_and_transient_error_retried(app):
    row = device()
    with patch.object(push, 'section_snapshot', return_value=[section()]):
        push.dispatch(lambda d,p: (500, 'InternalServerError'))
        assert row.active
        push.dispatch(lambda d,p: (410, 'Unregistered'))
        assert not row.active
        assert push.dispatch(lambda d,p: pytest.fail('inactive token used')) == 0


def test_workspace_switch_moves_single_installation(app):
    client = app.test_client()
    body = dict(installation_id=str(uuid4()), token='ac'*32, environment='sandbox', language='he')
    for wid in (1, 2, 2):
        response = client.post('/push-devices/register', json=body, headers={'X-Workspace-Id': str(wid)})
        assert response.status_code == 200
        assert response.json['enabled']
    rows = PushDevice.query.all()
    assert len(rows) == 1 and rows[0].workspace_id == 2
    with patch.object(push, 'section_snapshot', side_effect=lambda wid: [section(str(wid))]):
        deliveries = []
        push.dispatch(lambda d,p: (deliveries.append(p) or (200,'')))
    assert [p['workspace_id'] for p in deliveries] == [2]


def test_registration_permission_rotation_and_feature_gate(app, monkeypatch):
    client = app.test_client()
    body = dict(installation_id=str(uuid4()), token='ad'*32, environment='production')
    assert client.post('/push-devices/register', json=body).json['enabled']
    body['token'] = 'af'*32
    body['authorized'] = False
    assert not client.post('/push-devices/register', json=body).json['enabled']
    assert PushDevice.query.one().token == body['token']
    assert not PushDevice.query.one().active
    assert client.post('/push-devices/register', json={}).status_code == 400
    monkeypatch.setenv('APNS_ENABLED', 'false')
    assert client.post('/push-devices/register', json={}).json == {'enabled': False}
    assert push.dispatch() == 0


def test_live_snapshot_uses_current_tasks_and_workspace(app):
    from models import View, Task, ViewTaskMembership, Automation
    now = datetime.utcnow()
    db.session.add_all([
        View(id=1, workspace_id=1, name='Daily', layout_config={'sections':[{'key':'evening','name':'Evening'}]}),
        Task(id=1,title='Read',status='active'),
    ])
    db.session.flush()
    db.session.add(ViewTaskMembership(view_id=1, task_id=1, section_name='Evening'))
    db.session.add(Automation(id=1, workspace_id=1, name='Evening', kind='section_window',
        enabled=True, view_id=1, section_key='evening', window_opened_at=now,
        window_closes_at=now+timedelta(hours=1)))
    db.session.commit()
    assert len(push.section_snapshot(1, now)) == 1
    assert push.section_snapshot(2, now) == []
    db.session.get(Task,1).status='done'
    assert push.section_snapshot(1, now) == []
