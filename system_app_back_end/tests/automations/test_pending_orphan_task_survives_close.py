from datetime import datetime, timedelta

from tests.automations.test_review_lifecycle import database
from models import db, Automation, Task, View, ViewTaskMembership
from areas.automations.services import section_windows as windows


def setup_one_time_window():
    now = datetime(2026, 9, 13, 18)
    db.session.add(View(id=1, workspace_id=1, name='Trip', layout_config={
        'cadence': 'one_time', 'sections': [{'key': 'pack', 'name': 'Packing'}]}))
    window = Automation(id=2, workspace_id=1, name='Packing', kind='section_window',
        view_id=1, section_key='pack', schedule='once',
        window_duration_minutes=60, window_opened_at=now,
        window_closes_at=now + timedelta(hours=1))
    db.session.add(window)
    # An active orphan task (created directly in the view, no home list) and
    # a pending orphan task scheduled for a future day.
    db.session.add(Task(id=1, title='Buy tape', status='active', task_list_id=None))
    db.session.add(Task(
        id=2, title='Confirm flight', status='pending', task_list_id=None,
        due_date=now + timedelta(days=5),
    ))
    for tid in (1, 2):
        db.session.add(ViewTaskMembership(
            view_id=1, task_id=tid, section_name='Packing', topic_key='',
        ))
    db.session.commit()
    return window, now


def test_pending_orphan_task_keeps_membership_and_is_not_archived(database):
    window, now = setup_one_time_window()
    windows._close_section_window(window)

    active = db.session.get(Task, 1)
    pending = db.session.get(Task, 2)

    # Existing behavior: an active orphan task is swept into the archive
    # when its one-time section closes.
    assert active.archived_at is not None
    assert ViewTaskMembership.query.filter_by(task_id=1).count() == 0

    # The bug: a pending task scheduled for a future day must survive the
    # window close untouched — it hasn't been missed, it just hasn't
    # activated yet.
    assert pending.archived_at is None
    assert ViewTaskMembership.query.filter_by(task_id=2).count() == 1
