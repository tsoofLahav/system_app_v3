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
