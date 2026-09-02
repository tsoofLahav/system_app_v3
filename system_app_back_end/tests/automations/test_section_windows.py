"""Section windows, leftover cadence, and complimentary placement rules."""

import inspect
from datetime import datetime, timezone

import pytest

from models import Automation, Task, AiAction
from areas.automations.routes import automations as automations_routes
from areas.automations.services import section_windows as windows
from areas.automations.services.steps import validate_steps
from areas.objects.services import task_ops
from scripts import run_automations as cron


def test_models_have_section_window_columns():
    auto_cols = {c.name for c in Automation.__table__.columns}
    assert {
        "kind",
        "view_id",
        "section_key",
        "window_duration_minutes",
        "window_opened_at",
        "window_closes_at",
        "pending_clear",
        "pending_user_input",
    } <= auto_cols
    task_cols = {c.name for c in Task.__table__.columns}
    assert {"source_automation_id", "complimentary_role", "complimentary_cycle"} <= task_cols
    action_cols = {c.name for c in AiAction.__table__.columns}
    assert {"requires_user_input", "user_input_prompt"} <= action_cols


def test_automation_to_dict_includes_window_fields():
    source = inspect.getsource(Automation.to_dict)
    assert "kind" in source
    assert "section_key" in source
    assert "window_duration_minutes" in source
    assert "pending_clear" in source


def test_task_to_dict_includes_complimentary_fields():
    source = inspect.getsource(Task.to_dict)
    assert "source_automation_id" in source
    assert "complimentary_role" in source


def test_ensure_section_keys_assigns_stable_key_and_routine_default():
    layout, changed = windows.ensure_section_keys(
        {"sections": [{"name": "Focus", "order": 0}]}
    )
    assert changed is True
    section = layout["sections"][0]
    assert section["key"]
    assert section["cadence"] == windows.CADENCE_ROUTINE
    again, changed_again = windows.ensure_section_keys(layout)
    assert changed_again is False
    assert again["sections"][0]["key"] == section["key"]


def test_section_cadence_reads_layout():
    layout = {
        "sections": [
            {"name": "Daily", "key": "abc", "cadence": "routine"},
            {"name": "Once", "key": "def", "cadence": "one_time"},
        ]
    }
    assert windows.section_cadence(layout, "abc") == "routine"
    assert windows.section_cadence(layout, "def") == "one_time"
    assert windows.section_name_for_key(layout, "def") == "Once"


def test_complimentary_titles():
    auto = Automation(name="Weekly brief", name_he="סקירה שבועית")
    titles = windows.complimentary_titles(auto)
    assert titles["input"] == "Weekly brief automation task"
    assert titles["review"] == "Weekly brief review task"
    assert titles["input_he"] == "סקירה שבועית משימת אוטומציה"
    assert titles["review_he"] == "סקירה שבועית משימת סקירה"


def test_ai_step_keeps_requires_user_input():
    steps = validate_steps(
        [
            {
                "kind": "ai",
                "prompt": "write it",
                "apply_mode": "review",
                "requires_user_input": True,
            }
        ]
    )
    assert steps[0]["requires_user_input"] is True


def test_window_is_open_accepts_aware_timestamptz():
    now = datetime(2026, 8, 30, 12, 0, 0)
    open_window = Automation(
        kind=windows.KIND_SECTION_WINDOW,
        window_opened_at=datetime(2026, 8, 30, 11, 0, 0, tzinfo=timezone.utc),
        window_closes_at=datetime(2026, 8, 30, 13, 0, 0, tzinfo=timezone.utc),
    )
    assert windows.window_is_open(open_window, now) is True
    after = datetime(2026, 8, 30, 14, 0, 0)
    assert windows.window_is_open(open_window, after) is False


def test_toggle_allows_complimentary_tasks():
    task = Task(title="x", status="active", complimentary_role="input")
    task_ops.toggle_task(task)
    assert task.status == "done"
    task_ops.toggle_task(task)
    assert task.status == "active"


def test_routes_expose_window_endpoints():
    source = inspect.getsource(automations_routes)
    assert "/automations/pending-clears" in source
    assert "/submit-input" in source
    assert "/clear-leftovers" in source
    assert "/review-status" in source
    assert "ensure_section_windows" in source
    assert "ensure_complimentary_tasks" in source


def test_cron_handles_section_windows_and_locked_clocks():
    source = inspect.getsource(cron.tick)
    assert "tick_section_window" in source
    assert "section window off" in source
    assert "KIND_SECTION_WINDOW" in source
    assert "activate_due_pending_tasks" in source


def test_leftover_clear_archives_one_time_and_unmarks_routine():
    source = inspect.getsource(windows.apply_leftover_clear)
    assert "CADENCE_ONE_TIME" in source
    assert "archived_at" in source
    assert "set_task_status" in source
    assert "CADENCE_ROUTINE" in source


def test_clean_duration_end_unmarks_without_confirm():
    source = inspect.getsource(windows.close_window_or_pending)
    assert "leftover_active_tasks" in source
    assert "clear_section_window_state" in source
    reset = inspect.getsource(windows.clear_section_window_state)
    assert "recycle_complimentary" in reset
    assert "_recycle_routine_section" in reset
    assert "pending_clear = None" in reset


def test_patch_clears_window_when_clock_changes():
    source = inspect.getsource(automations_routes.update_automation)
    assert "clock_changed" in source
    assert "clear_section_window_state" in source


def test_complimentary_placement_requires_routine():
    source = inspect.getsource(windows.ensure_complimentary_tasks)
    assert "routine section" in source
    assert "wanted_complimentary_roles" in source
    assert "for role in roles" in source


def test_wanted_complimentary_roles_are_independent():
    source = inspect.getsource(windows.wanted_complimentary_roles)
    assert "automation_requires_user_input" in source
    assert "automation_needs_review" in source
    assert "ROLE_INPUT" in source
    assert "ROLE_REVIEW" in source


def test_linked_standard_skipped_when_window_off():
    source = inspect.getsource(cron.tick)
    assert "row.view_id and row.section_key" in source
    assert "window.enabled" in source


def test_input_topics_uses_resolved_scope():
    source = inspect.getsource(windows.input_topics)
    assert "resolve_scope" in source
    assert "topic_ids" in source
    assert "is_template" in source


def test_review_status_is_gated_on_pending_reviews():
    source = inspect.getsource(windows.review_status)
    assert "has_pending_review" in source
    assert "AgentPendingReview" in source
    assert "input_received" in source


def test_toggle_route_uses_task_ops():
    from areas.objects.routes import tasks as tasks_routes

    source = inspect.getsource(tasks_routes.toggle_task)
    assert "task_ops.toggle_task" in source


def test_format_user_input_keeps_multiline_per_topic():
    note = "line one\n\nline two with details"
    formatted = windows.format_user_input_for_prompt(
        {"by_topic": {"Kitchen": note, "Garden": "water the beds"}}
    )
    assert "--- user input · Kitchen ---" in formatted
    assert "--- user input · Garden ---" in formatted
    assert "line one\n\nline two with details" in formatted
    assert formatted.index("Kitchen") < formatted.index("line one")
    assert "- Kitchen:" not in formatted


def test_format_user_input_plain_text_when_no_topics():
    assert windows.format_user_input_for_prompt({"text": "hello"}) == "hello"


def test_cleaned_user_input_text_rejects_over_budget():
    assert windows.cleaned_user_input_text("  ok  ") == "ok"
    with pytest.raises(ValueError, match="longer than"):
        windows.cleaned_user_input_text(
            "x" * (windows.COMPLIMENTARY_INPUT_MAX_CHARS + 1)
        )
