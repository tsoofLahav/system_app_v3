from datetime import datetime, timedelta
from unittest.mock import patch

from flask import current_app

from areas.automations.routes import automations
from areas.automations.services import input_queue, run_automation, section_windows
from models import Automation, AutomationRun, Task, db
from tests.automations.test_review_lifecycle import database


def test_submission_is_durable_deduplicated_and_drained(database):
    app = current_app._get_current_object()
    app.register_blueprint(automations.automations_bp)
    client = app.test_client()
    body = {"text": "saved answer", "submission_id": "a" * 32}
    with patch.object(run_automation, "run_steps") as run_steps:
        response = client.post("/automations/1/submit-input", json=body)
        assert response.status_code == 202
        run_id = response.json["run"]["id"]
        assert response.json["run"]["status"] == "queued"
        run_steps.assert_not_called()

        duplicate = client.post("/automations/1/submit-input", json=body)
        assert duplicate.json["run"]["id"] == run_id
        concurrent = client.post(
            "/automations/1/submit-input",
            json={**body, "submission_id": "b" * 32},
        )
        assert concurrent.status_code == 409

        run_steps.return_value = {"status": "ok", "steps": [], "scope": {}}
        input_queue.drain_input_queue()
        run_steps.assert_called_once()
        assert run_steps.call_args.kwargs["user_input"]["text"] == "saved answer"
        assert db.session.get(AutomationRun, run_id).status == "completed"
        assert client.post("/automations/1/submit-input", json=body).json["run"]["id"] == run_id
        assert AutomationRun.query.count() == 1


def test_interrupted_legacy_submission_preserves_input_and_reopens_task(database):
    automation = db.session.get(Automation, 1)
    note = section_windows.store_user_input(automation, {"text": "saved answer"})
    task = Task(
        title="Input", status="active", source_automation_id=1,
        complimentary_role=section_windows.ROLE_INPUT,
        complimentary_cycle={"input_received": True},
    )
    run = run_automation.new_run(automation, "user_input", note, status="running")
    run.started_at = datetime.utcnow() - timedelta(minutes=10)
    db.session.add(task)
    db.session.commit()

    input_queue.reconcile_input_runs(1)
    db.session.commit()
    assert run.status == "failed"
    assert run.finished_at is not None
    assert not task.complimentary_cycle.get("input_received")
    assert automation.pending_user_input == run.event_context["user_input"] == note
