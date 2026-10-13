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
