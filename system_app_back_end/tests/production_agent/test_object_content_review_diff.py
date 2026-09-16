"""A review-mode edit that fills an existing (or just-created) embed's
content — a task list's tasks, an info piece's body — must show that content
in the diff. Regression: object_updates were never applied to the DB until
finish, but the diff rendered straight from live DB objects, so the "new"
side looked identical to the "old" side and the edit appeared to vanish."""

import pytest
from flask import Flask
from sqlalchemy.ext.compiler import compiles
from sqlalchemy.dialects.postgresql import JSONB

from models import db, Workspace, Topic, File, Task, AgentPendingReview
from areas.files.services.document_v3 import empty_document_json
from areas.objects.services.create_embed import create_embed_in_file
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
        db.session.add(File(id=1, topic_id=1, name="Doc", document_json=empty_document_json()))
        db.session.commit()
        yield
        db.session.remove()
        db.drop_all()


def test_filling_an_empty_task_list_shows_the_new_tasks_in_the_diff(database):
    # Simulate create_object having already run: a real, empty task list
    # embed whose pointer is already live in the file.
    file = db.session.get(File, 1)
    embed = create_embed_in_file(file, type_="task_list", title="Extracted")
    db.session.commit()
    object_id = embed.id
    before = file.document_json

    document_text = (
        f'[TASK_LIST id="{object_id}" title="Extracted"]\n'
        "ACTIVE:\n- [ ] Task A\n- [ ] Task B\n[/TASK_LIST]"
    )
    result = apply_document_text(
        1, document_text, scope={"workspace_id": 1},
        write_mode="review", tool_name="patch_file",
    )

    assert "error" not in result
    assert result["applied"] is False
    new_text = result["review"]["new_document_text"]
    old_text = result["review"]["old_document_text"]
    assert "Task A" in new_text and "Task B" in new_text
    assert "Task A" not in old_text and "Task B" not in old_text

    # Nothing applied to the live file or the live task rows yet.
    assert db.session.get(File, 1).document_json == before
    assert Task.query.filter_by(task_list_id=embed.task_list_id).count() == 0

    saved_ids = upsert_pending_from_proposals(
        workspace_id=1, run_key="run-1", proposed_changes=[result]
    )
    assert saved_ids
    pending = AgentPendingReview.query.filter_by(file_id=1).first()
    hunks = build_hunks(pending.old_agent_text, pending.new_agent_text)
    assert hunks, "filling an object's content must be a real, decidable hunk"
    assert any("Task A" in "\n".join(h["new_lines"]) for h in hunks)

    decisions = [{"hunk_id": h["id"], "choice": "accept"} for h in hunks]
    outcome = finish_pending(1, decisions=decisions)
    assert outcome.get("ok") is True

    tasks = Task.query.filter_by(task_list_id=embed.task_list_id).all()
    assert {t.title for t in tasks} == {"Task A", "Task B"}
