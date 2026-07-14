"""Tests for file_moved event matching on project_update rules."""

from types import SimpleNamespace

from services.automation_dispatcher import rule_matches_file_event


def _rule(*, event="file_moved", topic_type="project"):
    return SimpleNamespace(
        trigger_type="event",
        key="project_update",
        action_type="project_update",
        params={
            "event": event,
            "scope": {"kind": "topic_type", "topic_type": topic_type},
            "bindings": [
                {"role": "log", "match": {"type": "log"}},
                {"role": "plan", "match": {"type": "plan"}},
            ],
        },
    )


def _file(*, topic_id=5, file_type="log"):
    return SimpleNamespace(
        id=12,
        topic_id=topic_id,
        type=file_type,
        name="Log",
        is_main=False,
    )


def test_rule_matches_file_moved_for_log_in_project_scope(monkeypatch):
    rule = _rule()
    file = _file()

    monkeypatch.setattr(
        "services.automation_dispatcher.topic_in_scope",
        lambda _rule, topic_id: topic_id == 5,
    )

    assert rule_matches_file_event(
        rule,
        file,
        event_context={"change": "file_moved"},
    )


def test_rule_ignores_non_move_events(monkeypatch):
    rule = _rule()
    file = _file()

    monkeypatch.setattr(
        "services.automation_dispatcher.topic_in_scope",
        lambda _rule, topic_id: topic_id == 5,
    )

    assert not rule_matches_file_event(
        rule,
        file,
        event_context={"change": "file_updated"},
    )


def test_rule_requires_project_scope(monkeypatch):
    rule = _rule()
    file = _file(topic_id=99)

    monkeypatch.setattr(
        "services.automation_dispatcher.topic_in_scope",
        lambda _rule, topic_id: topic_id == 5,
    )

    assert not rule_matches_file_event(
        rule,
        file,
        event_context={"change": "file_moved"},
    )
