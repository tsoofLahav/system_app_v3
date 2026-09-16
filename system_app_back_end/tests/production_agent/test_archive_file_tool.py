"""archive_file tool — always applies immediately, even under review mode."""

from unittest.mock import patch

import pytest
from flask import Flask
from sqlalchemy.ext.compiler import compiles
from sqlalchemy.dialects.postgresql import JSONB

from models import db, Workspace, Topic, File, AgentPendingReview
from areas.files.services.document_v3 import empty_document_json
from areas.production_agent.services import runner
from areas.production_agent.services.archive_file_tool import archive_file_tool


@compiles(JSONB, "sqlite")
def jsonb_sqlite(type_, compiler, **kw):
    return "JSON"


@pytest.fixture
def database():
    app = Flask(__name__)
    app.config.update(SQLALCHEMY_DATABASE_URI="sqlite://", TESTING=True)
    db.init_app(app)
    with app.app_context():
        db.create_all()
        db.session.add(Workspace(id=1, name="Personal"))
        db.session.add(Topic(id=1, workspace_id=1, name="Notes"))
        db.session.add(File(id=1, topic_id=1, name="Doc", document_json=empty_document_json()))
        db.session.commit()
        yield
        db.session.remove()
        db.drop_all()


def test_archive_file_tool_archives_and_drops_pending_review(database):
    db.session.add(
        AgentPendingReview(
            file_id=1, workspace_id=1, topic_id=1,
            old_agent_text="old", new_agent_text="new",
        )
    )
    db.session.commit()

    result = archive_file_tool(
        file_id=1, scope={"workspace_id": 1}, write_mode="direct_apply"
    )
    assert result["applied"] is True

    file = db.session.get(File, 1)
    assert file.archived_at is not None
    assert AgentPendingReview.query.filter_by(file_id=1).first() is None


def test_archive_file_tool_notify_only_does_nothing(database):
    result = archive_file_tool(
        file_id=1, scope={"workspace_id": 1}, write_mode="notify_only"
    )
    assert result["applied"] is False
    assert db.session.get(File, 1).archived_at is None


def test_review_mode_run_still_archives_immediately(database):
    """Regression: archiving must not be held back or rolled back just
    because the run's apply_mode is 'review' — it is not a content edit."""
    with (
        patch.object(runner, "system_prompt_for_workspace", return_value="test"),
        patch.object(runner, "_model_for_workspace", return_value="test"),
        patch.object(runner, "create_conversation", return_value="conv-1"),
        patch.object(runner, "delete_conversation"),
        patch.object(runner, "create_response", return_value={}),
        patch.object(
            runner,
            "function_calls_from_response",
            side_effect=[
                [
                    {
                        "name": "archive_file",
                        "arguments": {"file_id": 1},
                        "call_id": "1",
                    }
                ],
                [],
            ],
        ),
        patch.object(runner, "output_text_from_response", return_value="Done"),
    ):
        result = runner.run_agent(
            prompt="Archive it",
            workspace_id=1,
            scope={},
            apply_mode="review",
            commit=False,
        )

    assert result["status"] == "ok"
    db.session.commit()
    db.session.expire_all()
    assert db.session.get(File, 1).archived_at is not None
