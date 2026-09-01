"""Inactive / pending task status rules (no database)."""

from datetime import date, datetime

from models import Task
from areas.objects.services.task_ops import (
    ACTIVE,
    DONE,
    INACTIVE,
    PENDING,
    set_task_status,
    should_activate_pending,
    sync_status_with_memberships,
    toggle_task,
    unmarked_status_for,
)
from scripts import run_automations as cron
import inspect


def test_toggle_inactive_and_pending_are_noop():
    parked = Task(title="x", status=INACTIVE)
    toggle_task(parked)
    assert parked.status == INACTIVE

    waiting = Task(title="x", status=PENDING)
    toggle_task(waiting)
    assert waiting.status == PENDING


def test_toggle_active_without_view_becomes_inactive_when_unmarked():
    task = Task(title="x", status=ACTIVE)
    toggle_task(task)
    assert task.status == DONE
    toggle_task(task)
    assert task.status == INACTIVE


def test_unmarked_status_without_id_is_inactive():
    task = Task(title="x", status=DONE)
    assert unmarked_status_for(task) == INACTIVE
    set_task_status(task, done=False)
    assert task.status == INACTIVE


def test_sync_pending_without_view_becomes_inactive():
    done = Task(title="x", status=DONE)
    sync_status_with_memberships(done)
    assert done.status == DONE

    pending = Task(title="x", status=PENDING)
    sync_status_with_memberships(pending)
    assert pending.status == INACTIVE


def test_should_activate_pending_uses_calendar_day():
    today = date(2026, 9, 1)
    assert should_activate_pending(PENDING, datetime(2026, 9, 1), today) is True
    assert should_activate_pending(PENDING, datetime(2026, 8, 31), today) is True
    assert should_activate_pending(PENDING, datetime(2026, 9, 2), today) is False
    assert should_activate_pending(PENDING, None, today) is False
    assert should_activate_pending(ACTIVE, datetime(2026, 9, 1), today) is False


def test_cron_activates_due_pending_tasks():
    source = inspect.getsource(cron.tick)
    assert "activate_due_pending_tasks" in source
