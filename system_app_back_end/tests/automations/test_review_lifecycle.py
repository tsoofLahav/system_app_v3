from datetime import datetime, timedelta
from unittest.mock import patch
import pytest
from flask import Flask
from sqlalchemy.ext.compiler import compiles
from sqlalchemy.dialects.postgresql import JSONB
from models import db, Workspace, Topic, File, View, Task, ViewTaskMembership, Automation, AutomationRun, AgentPendingReview
from areas.automations.services import section_windows as windows
from areas.production_agent.services import runner
from areas.automations.services.actions.ai import ai

@compiles(JSONB, 'sqlite')
def jsonb_sqlite(type_, compiler, **kw):
    return 'JSON'

@pytest.fixture
def database():
    app = Flask(__name__)
    app.config.update(SQLALCHEMY_DATABASE_URI='sqlite://', TESTING=True)
    db.init_app(app)
    with app.app_context():
        db.create_all()
        db.session.add(Workspace(id=1, name='Personal'))
        db.session.add(Topic(id=1, workspace_id=1, name='Process'))
        for fid in (10, 20, 101):
            db.session.add(File(id=fid, topic_id=1, name=str(fid), document_json='original'))
        db.session.add(Automation(id=1, workspace_id=1, name='Review'))
        db.session.commit()
        yield
        db.session.remove()
        db.drop_all()


def test_review_ids_and_completion(database):
    automation = db.session.get(Automation, 1)
    db.session.add_all([
        AgentPendingReview(id=101, file_id=10, workspace_id=1, topic_id=1),
        AgentPendingReview(id=102, file_id=20, workspace_id=1, topic_id=1),
        AgentPendingReview(id=103, file_id=101, workspace_id=1, topic_id=1),
        AutomationRun(automation_id=1, status='completed', result={
            'steps': [{'pending_review_ids': [102, 101, 102]}]}),
    ])
    with patch.object(windows, '_mark_complimentary') as mark:
        assert windows.review_status(automation)['file_ids'] == [20, 10]
        assert not windows.complete_review_if_clear(automation)
        db.session.delete(db.session.get(AgentPendingReview, 102))
        assert windows.review_status(automation)['file_ids'] == [10]
        assert not windows.complete_review_if_clear(automation)
        db.session.delete(db.session.get(AgentPendingReview, 101))
        assert windows.complete_review_if_clear(automation)
        mark.assert_called_once()

@pytest.mark.parametrize('status', [None, 'running', 'failed'])
def test_incomplete_run_cannot_finish_review(database, status):
    if status:
        db.session.add(AutomationRun(automation_id=1, status=status, result={}))
    with patch.object(windows, '_mark_complimentary') as mark:
        assert not windows.complete_review_if_clear(db.session.get(Automation, 1))
        mark.assert_not_called()

@pytest.mark.parametrize('mode,failure', [
    ('review', False), ('review', True), ('review', 'persist'),
    ('direct_apply', False), ('direct_apply', True),
])
def test_rollback_preserves_window_run_and_attention(database, failure, mode):
    now = datetime.utcnow()
    db.session.add(View(id=1, workspace_id=1, name='Weekly', layout_config={
        'sections': [{'key': 'sat', 'name': 'Saturday evening'}]}))
    db.session.add(Task(id=1, title='Still open', status='active'))
    db.session.add(Task(id=2, title='Completed review', status='done'))
    db.session.add(ViewTaskMembership(view_id=1, task_id=2, section_name='Saturday evening'))
    db.session.add(ViewTaskMembership(view_id=1, task_id=1, section_name='Saturday evening'))
    window = Automation(workspace_id=1, name='Window', kind='section_window',
                        view_id=1, section_key='sat', window_opened_at=now,
                        window_closes_at=now+timedelta(hours=2))
    db.session.add(window)
    run = AutomationRun(automation_id=1, status='running')
    db.session.add(run)
    def dispatch(*args):
        db.session.get(File, 10).document_json = 'speculative'
        db.session.flush()
        if failure is True:
            raise RuntimeError('AI failed')
        return {'tool': 'patch_file', 'review': mode == 'review',
                'applied': mode == 'direct_apply', 'file_id': 10}
    def persist(**kwargs):
        db.session.add(AgentPendingReview(id=101, file_id=10, workspace_id=1, topic_id=1))
        db.session.flush()
        if failure == 'persist':
            raise RuntimeError('review storage failed')
        return [101]
    with (patch.object(runner, 'system_prompt_for_workspace', return_value='test'),
          patch.object(runner, '_model_for_workspace', return_value='test'),
          patch.object(runner, 'create_conversation', return_value='test-run'),
          patch.object(runner, 'delete_conversation'),
          patch.object(runner, 'create_response', return_value={}),
          patch.object(runner, 'function_calls_from_response', side_effect=[
              [{'name': 'patch_file', 'arguments': {}, 'call_id': '1'}], []]),
          patch.object(runner, 'output_text_from_response', return_value='Done'),
          patch.object(runner, '_dispatch_tool', side_effect=dispatch),
          patch.object(runner, 'upsert_pending_from_proposals', side_effect=persist)):
        result = runner.run_agent(prompt='Review', workspace_id=1, scope={},
                                  apply_mode=mode, commit=False)
    assert result['status'] == ('error' if failure else 'ok')
    assert db.session.get(File, 10).document_json == (
        'speculative' if mode == 'direct_apply' and not failure else 'original')
    db.session.commit()
    db.session.expire_all()
    assert db.session.get(AutomationRun, run.id) is not None
    assert (db.session.get(AgentPendingReview, 101) is not None) == (not failure and mode == 'review')
    assert windows.attention_for_window(db.session.get(Automation, window.id), now)


def test_each_topic_and_aggregated_reviews():
    with patch('areas.automations.services.actions.ai.run_agent', side_effect=[
        {'status': 'ok', 'pending_review_ids': [101]},
        {'status': 'ok', 'pending_review_ids': [102, 103]},
        {'status': 'ok', 'pending_review_ids': []},
    ]) as agent:
        result = ai(workspace_id=1, resolved_scope={'topic_ids': [1, 2, 3]},
                    params={'prompt': 'Review', 'per_topic': True}, now=datetime.utcnow())
    assert [c.kwargs['scope']['topic_ids'] for c in agent.call_args_list] == [[1], [2], [3]]
    assert all(c.kwargs['commit'] is False for c in agent.call_args_list)
    assert result['pending_review_ids'] == [101, 102, 103]
    assert len(result['topic_results']) == 3


def test_partial_failure_preserves_review_ids():
    with patch('areas.automations.services.actions.ai.run_agent', side_effect=[
        {'status': 'ok', 'pending_review_ids': [101]},
        {'status': 'error', 'error': 'unavailable'},
    ]) as agent:
        result = ai(workspace_id=1, resolved_scope={'topic_ids': [1, 2, 3]},
                    params={'prompt': 'Review', 'per_topic': True}, now=datetime.utcnow())
    assert result['error'] == 'unavailable'
    assert result['pending_review_ids'] == [101]
    assert agent.call_count == 2


def test_type_scope_activates_per_topic_execution():
    from areas.automations.services import run_automation
    with (patch.object(run_automation, 'resolve_scope', return_value={'topic_ids': [1, 2]}),
          patch.dict(run_automation.ACTIONS, {'ai': lambda **kw: {'per_topic': kw['params'].get('per_topic')}})):
        result = run_automation.run_steps(workspace_id=1, scope={'kind': 'topic_type'},
                                          steps=[{'kind': 'ai', 'prompt': 'Review'}])
    assert result['steps'][0]['per_topic'] is True
