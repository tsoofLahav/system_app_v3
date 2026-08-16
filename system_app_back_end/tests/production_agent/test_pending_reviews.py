"""Unit tests for pending review merge / hunks."""

from areas.production_agent.services.pending_reviews import (
    _coalesce_opcodes,
    build_hunks,
    merge_agent_text,
)


def test_build_hunks_add_remove_change():
    old = "a\nb\nc\n"
    new = "a\nB\nc\nd\n"
    hunks = build_hunks(old, new)
    ops = {h["op"] for h in hunks}
    assert "change" in ops
    assert "add" in ops


def test_single_line_edit_is_one_change_hunk():
    old = "a\nb\nc\n"
    new = "a\nB\nc\n"
    hunks = build_hunks(old, new)
    assert len(hunks) == 1
    assert hunks[0]["op"] == "change"
    assert hunks[0]["old_lines"] == ["b"]
    assert hunks[0]["new_lines"] == ["B"]


def test_accept_change_replaces_not_both():
    """Regression: accept edit must not keep old line and add new."""
    old = "a\nb\nc\n"
    new = "a\nB\nc\n"
    hunks = build_hunks(old, new)
    decisions = [{"hunk_id": h["id"], "choice": "accept"} for h in hunks]
    text, err = merge_agent_text(old, new, decisions)
    assert err is None
    lines = text.splitlines()
    assert lines == ["a", "B", "c"]
    assert lines.count("b") == 0


def test_coalesce_adjacent_delete_insert_to_replace():
    # Simulate difflib emitting delete then insert instead of replace.
    raw = [
        ("equal", 0, 1, 0, 1),
        ("delete", 1, 2, 1, 1),
        ("insert", 2, 2, 1, 2),
        ("equal", 2, 3, 2, 3),
    ]
    coalesced = _coalesce_opcodes(raw)
    assert coalesced == [
        ("equal", 0, 1, 0, 1),
        ("replace", 1, 2, 1, 2),
        ("equal", 2, 3, 2, 3),
    ]


def test_coalesce_adjacent_insert_delete_to_replace():
    raw = [
        ("insert", 1, 1, 1, 2),
        ("delete", 1, 2, 2, 2),
    ]
    coalesced = _coalesce_opcodes(raw)
    assert coalesced == [("replace", 1, 2, 1, 2)]


def test_pure_insert_and_delete_unchanged():
    old = "a\nc\n"
    new = "a\nb\nc\n"
    hunks = build_hunks(old, new)
    assert len(hunks) == 1
    assert hunks[0]["op"] == "add"
    assert hunks[0]["new_lines"] == ["b"]

    old2 = "a\nb\nc\n"
    new2 = "a\nc\n"
    hunks2 = build_hunks(old2, new2)
    assert len(hunks2) == 1
    assert hunks2[0]["op"] == "remove"
    assert hunks2[0]["old_lines"] == ["b"]


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
