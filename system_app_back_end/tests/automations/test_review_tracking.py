from tests.automations.test_review_lifecycle import database
from models import db, Automation, AutomationRun, AgentPendingReview, Topic, Task, File
from areas.automations.services.review_tracking import dismiss_task_reviews, acknowledge_topic, pending_for_run, topic_review_state
from areas.automations.services.section_windows import review_status


def seed():
    db.session.add(Topic(id=2, workspace_id=1, name='Sleep'))
    task = Task(title='Review', status='active', source_automation_id=1, complimentary_role='review')
    db.session.add(task)
    db.session.get(File, 20).topic_id = 2
    refs = []
    for rid, fid, tid in [(101, 10, 1), (102, 20, 2)]:
        db.session.add(AgentPendingReview(id=rid, file_id=fid, topic_id=tid, workspace_id=1, run_key='original', old_agent_text='old', new_agent_text='new'))
        refs.append({'id': rid, 'file_id': fid, 'topic_id': tid, 'run_key': 'original'})
    run = AutomationRun(automation_id=1, status='completed', result={'review_refs': refs, 'steps': [{'pending_review_ids': [101,102]}]},
                        event_context={'review_topic_ids': [1,2], 'reviewed_topic_ids': []})
    db.session.add(run)
    db.session.commit()
    return task, run


def test_dismiss_only_owned_generation(database):
    task, run = seed()
    newer = db.session.get(AgentPendingReview, 102)
    newer.run_key = 'new-manual-run'
    dismiss_task_reviews(task)
    db.session.flush()
    assert db.session.get(AgentPendingReview, 101) is None
    assert db.session.get(AgentPendingReview, 102) is newer
    assert run.event_context['review_dismissed'] is True


def test_topic_completion_removes_only_finished_topic(database):
    task, run = seed()
    topic = db.session.get(Topic, 1)
    assert topic_review_state(topic)['run_ids'] == [run.id]
    acknowledge_topic(topic, [run.id])
    assert run.event_context['reviewed_topic_ids'] == []
    db.session.delete(db.session.get(AgentPendingReview, 101))
    db.session.flush()
    acknowledge_topic(topic, [run.id])
    assert run.event_context['reviewed_topic_ids'] == [1]
    assert task.status == 'active'
    assert [t['id'] for t in review_status(db.session.get(Automation,1))['topics']] == [2]
    db.session.delete(db.session.get(AgentPendingReview, 102))
    db.session.flush()
    acknowledge_topic(db.session.get(Topic,2), [run.id])
    assert task.status == 'done'
    assert not run.event_context.get('review_dismissed')


def test_unknown_legacy_ownership_is_not_deleted(database):
    task, run = seed()
    run.result = {'steps': [{'pending_review_ids':[101]}]}
    assert pending_for_run(run) == []
    dismiss_task_reviews(task)
    db.session.flush()
    assert db.session.get(AgentPendingReview, 101) is not None


def test_topic_lists_pending_files_without_visibility_filter(database):
    task, run = seed()
    state = topic_review_state(db.session.get(Topic,1))
    assert {f['id'] for f in state['files']} == {10}


def test_dismissal_during_generation_drops_late_result(database):
    from unittest.mock import patch
    from areas.automations.services import run_automation
    task = Task(title='Review', status='active', source_automation_id=1, complimentary_role='review')
    db.session.add(task)
    db.session.commit()
    def steps(**kwargs):
        dismiss_task_reviews(task)
        task.status = 'done'
        db.session.commit()  # Dismissal is visible before generation returns.
        db.session.add(AgentPendingReview(id=101, file_id=10, topic_id=1, workspace_id=1, run_key='late', old_agent_text='old', new_agent_text='new'))
        db.session.flush()
        return {'status':'ok', 'steps':[{'pending_review_ids':[101]}]}
    with patch.object(run_automation, 'run_steps', side_effect=steps):
        run = run_automation.run_automation(db.session.get(Automation,1), trigger_source='test')
    db.session.flush()
    assert db.session.get(AgentPendingReview,101) is None
    assert run.event_context['review_dismissed'] is True
