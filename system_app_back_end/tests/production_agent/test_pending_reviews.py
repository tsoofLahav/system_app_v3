"""Unit tests for pending review merge / hunks."""

from areas.production_agent.services.pending_reviews import (
    build_hunks,
    merge_agent_text,
)


def test_build_hunks_add_remove_change():
    old = "a\nb\nc\n"
    new = "a\nB\nc\nd\n"
    hunks = build_hunks(old, new)
    ops = {h["op"] for h in hunks}
    assert "change" in ops or "add" in ops


def test_merge_requires_all_decisions():
    old = "one\ntwo\n"
    new = "one\nTWO\nthree\n"
    hunks = build_hunks(old, new)
    assert hunks
    text, err = merge_agent_text(old, new, [])
    assert text is None
    assert err


def test_merge_accept_all_takes_new():
    old = "one\ntwo\n"
    new = "one\nTWO\n"
    hunks = build_hunks(old, new)
    decisions = [{"hunk_id": h["id"], "choice": "accept"} for h in hunks]
    text, err = merge_agent_text(old, new, decisions)
    assert err is None
    assert "TWO" in text
    assert "two" not in text.splitlines()


def test_merge_reject_all_keeps_old():
    old = "one\ntwo\n"
    new = "one\nTWO\n"
    hunks = build_hunks(old, new)
    decisions = [{"hunk_id": h["id"], "choice": "reject"} for h in hunks]
    text, err = merge_agent_text(old, new, decisions)
    assert err is None
    assert "two" in text
    assert "TWO" not in text


def test_merge_mixed_accept_reject():
    old = "a\nb\nc\n"
    new = "a\nB\nc\nd\n"
    hunks = build_hunks(old, new)
    assert any(h["op"] == "change" for h in hunks)
    assert any(h["op"] == "add" for h in hunks)
    decisions = [
        {
            "hunk_id": h["id"],
            "choice": "accept" if h["op"] == "add" else "reject",
        }
        for h in hunks
    ]
    text, err = merge_agent_text(old, new, decisions)
    assert err is None
    lines = text.splitlines()
    assert "b" in lines
    assert "B" not in lines
    assert "d" in lines
