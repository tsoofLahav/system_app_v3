from datetime import datetime, timedelta
from unittest.mock import patch
import pytest
from tests.automations.test_review_lifecycle import database
from models import db, Automation, Task, View, ViewTaskMembership, SkippedTask, File
from areas.automations.services import section_windows as windows
from areas.objects.services.skipped_tasks import record_skip
from areas.objects.services.task_ops import set_task_status


def setup_window(cadence='routine'):
    now = datetime(2026, 9, 13, 18)
    db.session.add(View(id=1, workspace_id=1, name='Weekly', layout_config={
        'cadence': cadence, 'sections': [{'key': 'sat', 'name': 'Evening'}]}))
    window = Automation(id=2, workspace_id=1, name='Evening', kind='section_window',
        view_id=1, section_key='sat', schedule='weekly SAT 18:00',
        window_duration_minutes=60, window_opened_at=now,
        window_closes_at=now+timedelta(hours=1))
    db.session.add(window)
    for tid in (1, 2):
        db.session.add(Task(id=tid, title=f'Task {tid}', status='active'))
        db.session.add(ViewTaskMembership(view_id=1, task_id=tid, section_name='Evening', topic_key='topic_1'))
    db.session.commit()
    return window, now


def test_extension_survives_next_schedule_and_closes_when_finished(database):
    window, now = setup_window()
    windows.close_window_or_pending(window, now+timedelta(hours=2))
    windows.apply_leftover_clear(window, disposition='continue')
    assert windows.window_is_open(window, now+timedelta(days=30))
    assert window.schedule == 'weekly SAT 18:00'
    assert window.window_duration_minutes == 60
    with patch.object(windows, '_fire_linked_at_start') as fire:
        windows.tick_section_window(window, now=now+timedelta(days=7), action='run', planned=now+timedelta(days=14))
        fire.assert_not_called()
    assert window.window_opened_at == now
    set_task_status(db.session.get(Task, 1), done=True)
    windows.close_expired_section_windows(1)
    assert windows.window_is_open(window)
    set_task_status(db.session.get(Task, 2), done=True)
    windows.close_expired_section_windows(1)
    assert window.window_opened_at is None
    assert SkippedTask.query.count() == 0


def test_report_records_only_still_active_tasks_without_files(database):
    window, now = setup_window()
    windows.close_window_or_pending(window, now+timedelta(hours=2))
    set_task_status(db.session.get(Task, 2), done=True)
    initial_files = File.query.count()
    result = windows.apply_leftover_clear(window, disposition='report')
    assert result['skipped'] == 1
    assert db.session.get(Task, 1).status == 'skipped'
    assert db.session.get(Task, 2).status == 'done'
    row = SkippedTask.query.one()
    assert (row.task_id, row.topic_id, row.view_name, row.section_name) == (1, 1, 'Weekly', 'Evening')
    assert row.window_opened_at == now
    assert File.query.count() == initial_files
    windows.apply_leftover_clear(window, disposition='report')
    assert SkippedTask.query.count() == 1
    with patch.object(windows, '_fire_linked_at_start'):
        windows.open_window(window, now+timedelta(days=7))
    assert db.session.get(Task, 1).status == 'active'
    record_skip(db.session.get(Task, 1), window, 'Evening')
    assert SkippedTask.query.count() == 2


def test_done_is_not_a_skip_and_no_recycling_at_close(database):
    window, now = setup_window()
    windows.close_window_or_pending(window, now+timedelta(hours=2))
    result = windows.apply_leftover_clear(window, disposition='dismiss')
    assert result['marked_done'] == 2
    assert all(t.status == 'done' for t in Task.query.all())
    assert SkippedTask.query.count() == 0


def test_skip_history_survives_rename_and_source_deletion(database):
    window, _ = setup_window()
    task = db.session.get(Task, 1)
    record_skip(task, window, 'Evening')
    task.title = 'Renamed'
    task.status = 'active'
    record_skip(task, window, 'Evening')
    assert SkippedTask.query.count() == 1
    db.session.delete(task)
    db.session.flush()
    assert SkippedTask.query.one().task_title == 'Task 1'


def test_one_time_skips_do_not_create_archive_report(database):
    window, now = setup_window('one_time')
    before = File.query.count()
    windows.close_window_or_pending(window, now+timedelta(hours=2))
    windows.apply_leftover_clear(window, disposition='report')
    assert File.query.count() == before
    assert SkippedTask.query.count() == 2
    assert ViewTaskMembership.query.count() == 0


def test_skip_endpoint_requires_open_correct_section(database):
    from flask import current_app
    from areas.objects.routes.tasks import tasks_bp
    current_app.register_blueprint(tasks_bp)
    client = current_app.test_client()
    window, _ = setup_window()
    window.window_closes_at = datetime.utcnow()+timedelta(hours=1)
    db.session.commit()
    response = client.post('/tasks/1/skip', json={'automation_id': window.id})
    assert response.status_code == 200
    assert response.json['status'] == 'skipped'
    assert client.post('/tasks/1/skip', json={'automation_id': window.id}).status_code == 200
    assert SkippedTask.query.count() == 1
    window.window_closes_at = datetime.utcnow()-timedelta(hours=1)
    db.session.commit()
    with pytest.raises(ValueError, match='not active'):
        client.post('/tasks/2/skip', json={'automation_id': window.id})
    assert db.session.get(Task, 2).status == 'active'


def test_skip_preserves_home_list_and_topic_snapshot(database):
    from models import TaskList, ObjectEmbed
    window, _ = setup_window()
    db.session.add(TaskList(id=1, title="Daily journal"))
    db.session.add(ObjectEmbed(id=1, type="task_list", file_id=10, task_list_id=1))
    task = db.session.get(Task, 1)
    task.task_list_id = 1
    db.session.flush()
    row = record_skip(task, window, 'Evening')
    assert (row.task_list_id, row.task_list_title, row.topic_id, row.topic_name) == (1, 'Daily journal', 1, 'Process')


def test_skipped_agent_text_roundtrip_preserves_status():
    from areas.files.services.document_agent_text import _task_list_section, parse_agent_text
    text = _task_list_section(1, {'tasks': [
        {'id': 1, 'title': 'Not today', 'status': 'skipped'},
        {'id': 2, 'title': 'Finished', 'status': 'done'},
    ]})
    parsed = parse_agent_text(text)
    tasks = parsed['object_updates'][1]['tasks']
    assert {task['title']: task['status'] for task in tasks} == {'Not today': 'skipped', 'Finished': 'done'}


def test_late_complimentary_completion_does_not_overwrite_skip(database):
    window, _ = setup_window()
    task = db.session.get(Task, 1)
    task.source_automation_id = 1
    task.complimentary_role = 'review'
    task.status = 'skipped'
    db.session.flush()
    windows._mark_complimentary(db.session.get(Automation, 1), 'review', done=True)
    assert task.status == 'skipped'
