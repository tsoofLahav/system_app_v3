"""Process submitted section input in the existing automation cron."""

import logging
from datetime import datetime, timedelta

from sqlalchemy import text

from models import Automation, AutomationRun, db
from .run_automation import execute_run
from .section_windows import finish_input_run

logger = logging.getLogger(__name__)
LOCK_NAMESPACE = 107016
QUEUE_WAIT_LIMIT = timedelta(minutes=15)
LEGACY_RUN_LIMIT = timedelta(minutes=5)


def _input_runs():
    return AutomationRun.query.filter_by(trigger_source="user_input")


def active_input_run(automation_id):
    return (
        _input_runs().filter(
            AutomationRun.automation_id == automation_id,
            AutomationRun.status.in_(("queued", "running")),
        ).order_by(AutomationRun.id.desc()).first()
    )


def _try_lock(connection, run_id, *, transaction=False):
    function = (
        "pg_try_advisory_xact_lock" if transaction else "pg_try_advisory_lock"
    )
    return connection.execute(
        text(f"SELECT {function}(:namespace, :run_id)"),
        {"namespace": LOCK_NAMESPACE, "run_id": run_id},
    ).scalar_one()


def _fail(run, automation, message, now):
    run.status = "failed"
    run.error = message
    run.finished_at = now
    finish_input_run(automation, run)


def reconcile_input_runs(workspace_id):
    """Detect a dead cron process or an input that was never picked up."""
    now = datetime.utcnow()
    candidates = (
        _input_runs().join(Automation, AutomationRun.automation_id == Automation.id)
        .filter(
            Automation.workspace_id == workspace_id,
            AutomationRun.status.in_(("queued", "running")),
        ).order_by(AutomationRun.automation_id, AutomationRun.id).all()
    )
    for candidate in candidates:
        managed = (candidate.event_context or {}).get("queued_input") is True
        if candidate.status == "queued":
            limit = QUEUE_WAIT_LIMIT
        elif not managed:
            limit = LEGACY_RUN_LIMIT
        else:
            limit = timedelta(0)
        if now - candidate.started_at.replace(tzinfo=None) < limit:
            continue
        if candidate.status == "running" and managed:
            if db.engine.dialect.name != "postgresql":
                continue
            if not _try_lock(db.session.connection(), candidate.id, transaction=True):
                continue
        # Use the same row-lock order as submission and the cron claim.
        automation = Automation.query.filter_by(id=candidate.automation_id).with_for_update().first()
        run = _input_runs().filter_by(id=candidate.id).populate_existing().first()
        if automation is None or run is None:
            continue
        if run.status == "queued":
            if now - run.started_at.replace(tzinfo=None) >= QUEUE_WAIT_LIMIT:
                _fail(run, automation, "The background worker did not pick up the input", now)
        elif run.status == "running":
            if (run.event_context or {}).get("queued_input"):
                if db.engine.dialect.name != "postgresql":
                    continue
                if not _try_lock(db.session.connection(), run.id, transaction=True):
                    continue
            _fail(run, automation, "The automation run was interrupted", now)


def drain_input_queue():
    queued = _input_runs().filter_by(status="queued").order_by(AutomationRun.id).all()
    ids = [(run.id, run.automation_id) for run in queued]
    db.session.rollback()
    for run_id, automation_id in ids:
        try:
            _process_input(run_id, automation_id)
        except Exception:
            db.session.rollback()
            logger.exception("Background automation run %s failed", run_id)


def _process_input(run_id, automation_id):
    # The session-level lock stays on a separate connection across commits.
    # PostgreSQL releases it automatically if the cron process exits.
    with db.engine.connect() as connection:
        postgres = connection.dialect.name == "postgresql"
        if postgres and not _try_lock(connection, run_id):
            return
        connection.commit()
        try:
            automation = Automation.query.filter_by(id=automation_id).with_for_update().first()
            run = _input_runs().filter_by(id=run_id, status="queued").first()
            if automation is None or run is None:
                db.session.rollback()
                return
            run.status = "running"
            run.started_at = datetime.utcnow()
            db.session.commit()
            try:
                execute_run(automation, run)
                db.session.commit()
            except Exception:
                db.session.rollback()
                _fail(run, automation, "Background automation execution failed", datetime.utcnow())
                db.session.commit()
                raise
        finally:
            if postgres:
                connection.execute(
                    text("SELECT pg_advisory_unlock(:namespace, :run_id)"),
                    {"namespace": LOCK_NAMESPACE, "run_id": run_id},
                )
