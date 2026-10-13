import pytest
from flask import current_app
from models import db, View, Task, ViewTaskMembership
from areas.objects.routes.views import views_bp
from tests.production_agent.test_object_content_review_diff import database


def test_cross_view_rewrite_rejected_without_losing_original_rows(database):
    current_app.register_blueprint(views_bp)
    db.session.add_all([View(id=1, workspace_id=1, name="Daily"),
                        View(id=2, workspace_id=1, name="Weekly"),
                        Task(id=1, title="Daily task"), Task(id=2, title="Weekly task")])
    db.session.flush()
    db.session.add_all([ViewTaskMembership(view_id=1, task_id=1, section_name="Morning"),
                        ViewTaskMembership(view_id=2, task_id=2, section_name="Weekend")])
    db.session.commit()
    client = current_app.test_client()
    response = client.put('/views/2/memberships', json={"memberships": [
        {"task_id": 1, "section_name": "Morning"},
    ]})
    assert response.status_code == 409
    weekly = ViewTaskMembership.query.filter_by(view_id=2).one()
    assert (weekly.task_id, weekly.section_name) == (2, "Weekend")
    response = client.put('/views/2/memberships', json={"memberships": [
        {"task_id": 2, "section_name": "Saturday", "order_index": 0},
    ]})
    assert response.status_code == 200
    assert ViewTaskMembership.query.filter_by(view_id=2).one().section_name == "Saturday"


@pytest.mark.parametrize("payload,status", [
    ({"memberships": []}, 409),
    ({"memberships": [{"task_id": 2}, {"task_id": 2}]}, 409),
    ({"memberships": [{"task_id": 2, "view_id": 1}]}, 409),
    ({"memberships": [{"task_id": 999}]}, 409),
    ({}, 400),
    ({"memberships": ["invalid"]}, 400),
])
def test_stale_or_malformed_save_preserves_memberships(database, payload, status):
    current_app.register_blueprint(views_bp)
    db.session.add(View(id=2, workspace_id=1, name="Weekly"))
    db.session.add(Task(id=2, title="Weekly task"))
    db.session.flush()
    row = ViewTaskMembership(view_id=2, task_id=2, section_name="Weekend")
    db.session.add(row)
    db.session.commit()
    original_id = row.id
    result = current_app.test_client().put('/views/2/memberships', json=payload)
    assert result.status_code == status
    db.session.expire_all()
    saved = ViewTaskMembership.query.filter_by(view_id=2).one()
    assert (saved.id, saved.task_id, saved.section_name) == (original_id, 2, "Weekend")


def test_reorder_updates_in_place_preserving_membership_identity(database):
    current_app.register_blueprint(views_bp)
    db.session.add(View(id=2, workspace_id=1, name="Weekly"))
    db.session.add_all([Task(id=2, title="A"), Task(id=3, title="B")])
    db.session.flush()
    db.session.add_all([ViewTaskMembership(view_id=2, task_id=i, section_name="Weekend") for i in (2, 3)])
    db.session.commit()
    original = {row.task_id: (row.id, row.created_at) for row in ViewTaskMembership.query.all()}
    response = current_app.test_client().put('/views/2/memberships', json={"memberships": [
        {"task_id": 3, "view_id": 2, "section_name": "Saturday", "order_index": 0},
        {"task_id": 2, "view_id": 2, "section_name": "Sunday", "order_index": 1},
    ]})
    assert response.status_code == 200
    rows = ViewTaskMembership.query.order_by(ViewTaskMembership.order_index).all()
    assert [row.task_id for row in rows] == [3, 2]
    assert {row.task_id: (row.id, row.created_at) for row in rows} == original
