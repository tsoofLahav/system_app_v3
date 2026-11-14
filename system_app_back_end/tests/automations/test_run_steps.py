"""Walking a series: order, stopping, and what the run record says."""

from unittest.mock import patch

from areas.automations.services import run_automation as runner


def _run(steps, actions):
    with (
        patch.object(runner, "ACTIONS", actions),
        patch.object(runner, "resolve_scope", return_value={"workspace_id": 1}),
    ):
        return runner.run_steps(workspace_id=1, scope={}, steps=steps)


def test_steps_run_in_order():
    seen = []

    def note(name):
        def action(**kwargs):
            seen.append(name)
            return {"ok": True, "summary": name}

        return action

    result = _run(
        [{"kind": "a"}, {"kind": "b"}],
        {"a": note("a"), "b": note("b")},
    )

    assert seen == ["a", "b"]
    assert result["status"] == "ok"
    assert [s["summary"] for s in result["steps"]] == ["a", "b"]


def test_a_failure_stops_the_rest():
    """"Unmark the list, then summarise it" reads wrong if the unmark failed."""
    later = []
    actions = {
        "bad": lambda **kwargs: {"error": "no topic"},
        "later": lambda **kwargs: later.append(1) or {"ok": True},
    }

    result = _run([{"kind": "bad"}, {"kind": "later"}], actions)

    assert later == []
    assert result["status"] == "failed"
    assert result["error"] == "no topic"
    assert len(result["steps"]) == 1


def test_a_raising_step_is_recorded_not_propagated():
    def explode(**kwargs):
        raise RuntimeError("database went away")

    result = _run([{"kind": "boom"}], {"boom": explode})

    assert result["status"] == "failed"
    assert "database went away" in result["error"]


def test_parameters_reach_the_action_without_the_kind():
    got = {}

    def action(**kwargs):
        got.update(kwargs)
        return {"ok": True}

    _run([{"kind": "a", "name": "Log", "topic_id": 3}], {"a": action})

    assert got["params"] == {"name": "Log", "topic_id": 3}
    assert got["workspace_id"] == 1


def test_an_unknown_kind_stops_the_series():
    result = _run([{"kind": "nope"}], {})
    assert result["status"] == "failed"
    assert result["steps"][0]["error"] == "unknown step"


def test_step_input_routes_by_position_even_for_repeated_actions():
    from areas.automations.services.section_windows import input_steps_version

    steps = [
        {"kind": "ai", "action_id": 1, "requires_user_input": True},
        {"kind": "ai", "action_id": 2},
        {"kind": "ai", "action_id": 1, "requires_user_input": True},
    ]
    notes = {"1": {"text": "first"}, "3": {"by_topic": {"4": "third"}}}
    seen = []

    def action(**kwargs):
        seen.append(kwargs["params"].get("user_input"))
        return {"ok": True}

    payload = {"by_step": notes, "steps_version": input_steps_version(steps)}
    with (
        patch.object(runner, "ACTIONS", {"ai": action}),
        patch.object(runner, "resolve_scope", return_value={"workspace_id": 1}),
    ):
        result = runner.run_steps(
            workspace_id=1, scope={}, steps=steps, user_input=payload
        )
        assert result["status"] == "ok"
        assert seen == [notes["1"], None, notes["3"]]

        seen.clear()
        result = runner.run_steps(
            workspace_id=1, scope={}, steps=steps[1:], user_input=payload
        )
        assert result["status"] == "failed"
        assert seen == []

        legacy = {"text": "shared"}
        result = runner.run_steps(
            workspace_id=1, scope={}, steps=steps, user_input=legacy
        )
        assert result["status"] == "ok"
        assert seen == [legacy, legacy, legacy]
