"""Placement changes and polling repair keep companion tasks in one section."""
import pytest
from flask import current_app

from tests.automations.test_review_lifecycle import database
from models import Automation, Task, View, ViewTaskMembership, db
from areas.automations.routes.automations import automations_bp
from areas.automations.services import section_windows as windows


def setup_placement():
    current_app.register_blueprint(automations_bp)
    for view_id in (1, 2):
        db.session.add(View(id=view_id, workspace_id=1, name=f'View {view_id}',
                            layout_config={'cadence': 'routine', 'sections': [
                                {'key': 'old', 'name': 'Old'},
                                {'key': 'new', 'name': 'New'},
                            ]}))
    automation = db.session.get(Automation, 1)
    automation.view_id = 1
    automation.section_key = 'old'
    automation.steps = [{'kind': 'ai', 'requires_user_input': True, 'apply_mode': 'review'}]
    tasks = windows.ensure_complimentary_tasks(automation)
    for task in tasks:
        task.status = 'done'
        task.complimentary_cycle = {'input_received': True}
    db.session.commit()
    return tasks


@pytest.mark.parametrize('view_id', [1, 2])
def test_patch_moves_both_roles_preserving_task_state(database, view_id):
    tasks = setup_placement()
    ids = [task.id for task in tasks]
    response = current_app.test_client().patch('/automations/1', json={
        'view_id': view_id, 'section_key': 'new'})
    assert response.status_code == 200
    assert sorted(task.id for task in Task.query.all()) == ids
    for task in tasks:
        membership = ViewTaskMembership.query.filter_by(task_id=task.id).one()
        assert (membership.view_id, membership.section_name) == (view_id, 'New')
        assert task.status == 'done'
        assert task.complimentary_cycle == {'input_received': True}


def test_list_repairs_duplicates_and_preserves_ordinary_memberships(database):
    tasks = setup_placement()
    automation = db.session.get(Automation, 1)
    automation.view_id = 2
    automation.section_key = 'new'
    for task in tasks:
        db.session.add(ViewTaskMembership(view_id=2, task_id=task.id, section_name='New'))
    ordinary = Task(title='Ordinary', status='active')
    db.session.add(ordinary)
    db.session.flush()
    for view_id in (1, 2):
        db.session.add(ViewTaskMembership(view_id=view_id, task_id=ordinary.id, section_name='Old'))
    db.session.commit()
    client = current_app.test_client()
    for _ in range(2):
        assert client.get('/automations?workspace_id=1').status_code == 200
        for task in tasks:
            membership = ViewTaskMembership.query.filter_by(task_id=task.id).one()
            assert (membership.view_id, membership.section_name) == (2, 'New')
        assert ViewTaskMembership.query.filter_by(task_id=ordinary.id).count() == 2
