"""create_object under review mode must not leak unreviewed, and must not
silently lose the proposal either (regression: both used to happen)."""

from unittest.mock import patch

import pytest
from flask import Flask
from sqlalchemy.ext.compiler import compiles
from sqlalchemy.dialects.postgresql import JSONB

from models import db, Workspace, Topic, File, ObjectEmbed, InformationPiece, AgentPendingReview
from areas.files.services.document_v3 import empty_document_json
from areas.production_agent.services import runner
from areas.production_agent.services.create_object_tool import create_object
from areas.production_agent.services.pending_reviews import (
    build_hunks,
    finish_pending,
    upsert_pending_from_proposals,
)


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


def test_review_mode_create_object_holds_back_live_content(database):
    file = db.session.get(File, 1)
    before = file.document_json

    result = create_object(
        file_id=1,
        type_="info",
        scope={"workspace_id": 1},
        write_mode="review",
        title="Extracted",
        body="Some extracted data",
    )

    assert result["applied"] is False
    assert "review" in result
    assert "Extracted" not in (before or "")
    assert "Extracted" in result["review"]["new_document_text"]
    assert "Extracted" not in result["review"]["old_document_text"]

    # The live file must not show the new object until the review finishes.
    live = db.session.get(File, 1)
    assert live.document_json == before

    # The object row is real (its content had to exist to be rendered) but is
    # not yet referenced anywhere.
    embed = ObjectEmbed.query.filter_by(file_id=1, type="info").first()
    assert embed is not None
    assert embed.information_id is not None


def test_review_mode_create_object_becomes_a_reviewable_add_hunk(database):
    result = create_object(
        file_id=1,
        type_="info",
        scope={"workspace_id": 1},
        write_mode="review",
        title="Extracted",
        body="Some extracted data",
    )

    saved_ids = upsert_pending_from_proposals(
        workspace_id=1, run_key="run-1", proposed_changes=[result]
    )
    assert saved_ids

    pending = AgentPendingReview.query.filter_by(file_id=1).first()
    assert pending is not None
    hunks = build_hunks(pending.old_agent_text, pending.new_agent_text)
    assert hunks, "the new object must show up as a real hunk, not an empty diff"
    assert any(h["op"] == "add" for h in hunks)
    assert any("Extracted" in "\n".join(h["new_lines"]) for h in hunks)

    decisions = [{"hunk_id": h["id"], "choice": "accept"} for h in hunks]
    outcome = finish_pending(1, decisions=decisions)
    assert outcome.get("ok") is True

    live = db.session.get(File, 1)
    assert "Extracted" in (live.document_json or "") or ObjectEmbed.query.filter_by(
        file_id=1
    ).count() >= 1
    embed = ObjectEmbed.query.filter_by(file_id=1, type="info").first()
    assert embed is not None
    info = db.session.get(InformationPiece, embed.information_id)
    assert info.body == "Some extracted data"
    # The pointer must actually be woven into the live document now.
    assert str(embed.id) in (live.document_json or "")


def test_review_mode_create_object_rejected_leaves_file_untouched(database):
    file = db.session.get(File, 1)
    before = file.document_json

    result = create_object(
        file_id=1,
        type_="info",
        scope={"workspace_id": 1},
        write_mode="review",
        title="Extracted",
        body="Some extracted data",
    )
    upsert_pending_from_proposals(workspace_id=1, run_key="run-1", proposed_changes=[result])
    pending = AgentPendingReview.query.filter_by(file_id=1).first()
    hunks = build_hunks(pending.old_agent_text, pending.new_agent_text)
    decisions = [{"hunk_id": h["id"], "choice": "reject"} for h in hunks]

    outcome = finish_pending(1, decisions=decisions)
    assert outcome.get("ok") is True

    live = db.session.get(File, 1)
    assert live.document_json == before


def test_review_only_run_still_keeps_the_created_object_row(database):
    """Regression: a pure review-mode run used to roll back create_object's
    row entirely, silently dropping that part of the proposal."""
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
                        "name": "create_object",
                        "arguments": {
                            "file_id": 1,
                            "type": "info",
                            "title": "Extracted",
                            "body": "Some extracted data",
                        },
                        "call_id": "1",
                    }
                ],
                [],
            ],
        ),
        patch.object(runner, "output_text_from_response", return_value="Done"),
    ):
        result = runner.run_agent(
            prompt="Extract",
            workspace_id=1,
            scope={},
            apply_mode="review",
            commit=False,
        )

    assert result["status"] == "ok"
    db.session.commit()
    db.session.expire_all()

    # The live file must still be untouched...
    assert "Extracted" not in (db.session.get(File, 1).document_json or "")
    # ...but the object itself, and a pending review pointing at it, survive.
    embed = ObjectEmbed.query.filter_by(file_id=1, type="info").first()
    assert embed is not None
    pending = AgentPendingReview.query.filter_by(file_id=1).first()
    assert pending is not None
    hunks = build_hunks(pending.old_agent_text, pending.new_agent_text)
    assert any("Extracted" in "\n".join(h["new_lines"]) for h in hunks)
