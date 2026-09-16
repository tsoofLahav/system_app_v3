"""create_file under review mode must not be silently rolled back — same bug
class as create_object: the file row is real, but nothing marked it as
needing to survive a pure review-mode run's tool savepoint."""

from unittest.mock import patch

import pytest
from flask import Flask
from sqlalchemy.ext.compiler import compiles
from sqlalchemy.dialects.postgresql import JSONB

from models import db, Workspace, Topic, File, AgentPendingReview
from areas.files.services.document_v3 import empty_document_json
from areas.production_agent.services import runner
from areas.production_agent.services.pending_reviews import (
    build_hunks,
    finish_pending,
    upsert_pending_from_proposals,
)
from areas.production_agent.services.write_tools import apply_document_text


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
        db.session.add(File(id=1, topic_id=1, name="Source", document_json=empty_document_json()))
        db.session.commit()
        yield
        db.session.remove()
        db.drop_all()


def test_review_only_run_still_keeps_the_created_file(database):
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
                        "name": "create_file",
                        "arguments": {"topic_id": 1, "name": "Split A"},
                        "call_id": "1",
                    }
                ],
                [],
            ],
        ),
        patch.object(runner, "output_text_from_response", return_value="Done"),
    ):
        result = runner.run_agent(
            prompt="Split it out",
            workspace_id=1,
            scope={},
            apply_mode="review",
            commit=False,
        )

    assert result["status"] == "ok"
    db.session.commit()
    db.session.expire_all()

    new_file = File.query.filter_by(topic_id=1, name="Split A").first()
    assert new_file is not None, "the created file must survive a pure review-mode run"


def test_filling_the_new_file_shows_as_a_whole_new_file_diff(database):
    new_file_result = None
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
                        "name": "create_file",
                        "arguments": {"topic_id": 1, "name": "Split A"},
                        "call_id": "1",
                    }
                ],
                [],
            ],
        ),
        patch.object(runner, "output_text_from_response", return_value="Done"),
    ):
        runner.run_agent(
            prompt="Split it out", workspace_id=1, scope={},
            apply_mode="review", commit=False,
        )
    db.session.commit()
    new_file = File.query.filter_by(topic_id=1, name="Split A").first()
    assert new_file is not None

    result = apply_document_text(
        new_file.id, "Split content moved here.",
        scope={"workspace_id": 1}, write_mode="review", tool_name="patch_file",
    )
    assert "error" not in result
    assert result["review"]["old_document_text"] == ""
    assert "Split content moved here." in result["review"]["new_document_text"]
    assert db.session.get(File, new_file.id).document_json == new_file.document_json

    upsert_pending_from_proposals(
        workspace_id=1, run_key="run-1", proposed_changes=[result]
    )
    pending = AgentPendingReview.query.filter_by(file_id=new_file.id).first()
    assert pending is not None
    hunks = build_hunks(pending.old_agent_text, pending.new_agent_text)
    assert hunks

    decisions = [{"hunk_id": h["id"], "choice": "accept"} for h in hunks]
    outcome = finish_pending(new_file.id, decisions=decisions)
    assert outcome.get("ok") is True
    assert "Split content moved here." in outcome.get("chosen_agent_text", "")
