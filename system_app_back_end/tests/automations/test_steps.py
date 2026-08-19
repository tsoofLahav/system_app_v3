"""A bad automation is refused when it is saved, not at 2am when it fires."""

from datetime import datetime

import pytest

from areas.automations.services.actions import ACTIONS
from areas.automations.services.steps import (
    STEP_SPECS,
    StepError,
    expand_name_tokens,
    validate_steps,
)


def test_every_declared_step_has_something_to_run():
    """`STEP_SPECS` and the action registry are two halves of one vocabulary."""
    assert set(STEP_SPECS) == set(ACTIONS)


def test_a_series_keeps_its_order():
    steps = validate_steps(
        [
            {"kind": "unmark_tasks", "task_list_id": 8},
            {"kind": "ai", "prompt": "summarise", "apply_mode": "review"},
        ]
    )
    assert [s["kind"] for s in steps] == ["unmark_tasks", "ai"]


def test_unknown_keys_are_dropped():
    steps = validate_steps([{"kind": "create_file", "name": "Log", "colour": "red"}])
    assert steps == [{"kind": "create_file", "name": "Log"}]


def test_an_ai_step_needs_a_prompt_or_a_saved_action():
    assert validate_steps([{"kind": "ai", "action_id": 3}])
    with pytest.raises(StepError, match="prompt or a saved action"):
        validate_steps([{"kind": "ai"}])


def test_apply_mode_is_checked():
    with pytest.raises(StepError, match="apply_mode"):
        validate_steps([{"kind": "ai", "prompt": "x", "apply_mode": "whenever"}])


def test_a_new_file_needs_a_name_or_a_slot():
    with pytest.raises(StepError, match="name or a template slot"):
        validate_steps([{"kind": "create_file", "name": "   "}])
    assert validate_steps([{"kind": "create_file", "template_slot": "doc"}]) == [
        {"kind": "create_file", "template_slot": "doc"}
    ]


def test_archiving_can_target_a_template_slot():
    assert validate_steps([{"kind": "archive_files", "template_slot": "doc"}]) == [
        {"kind": "archive_files", "template_slot": "doc"}
    ]


def test_archiving_with_no_filter_means_everything_in_scope():
    assert validate_steps([{"kind": "archive_files"}]) == [{"kind": "archive_files"}]
    assert validate_steps([{"kind": "archive_files", "older_than_days": 30}])


def test_unknown_kind_names_the_position():
    with pytest.raises(StepError, match="step 2"):
        validate_steps([{"kind": "unmark_tasks"}, {"kind": "send_email"}])


def test_steps_must_be_a_list():
    with pytest.raises(StepError):
        validate_steps({"kind": "ai", "prompt": "x"})


def test_name_tokens_move_with_the_calendar():
    when = datetime(2026, 8, 18, 9, 30)
    assert expand_name_tokens("Week of {date}", now=when) == "Week of 2026-08-18"
    assert expand_name_tokens("{weekday} log", now=when) == "Tuesday log"
    assert expand_name_tokens("{month} {year}", now=when) == "August 2026"


def test_a_name_without_tokens_is_left_alone():
    assert expand_name_tokens("Plans", now=datetime(2026, 8, 18)) == "Plans"
