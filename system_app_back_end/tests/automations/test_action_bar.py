"""Tests for AI bar slot rules (saved actions)."""

import pytest

from areas.automations.services.action_bar import (
    AI_BAR_SLOTS,
    first_free_slot,
    run_scope,
    slots_after_claim,
    slots_from_order,
)


def test_slots_from_order_numbers_from_one():
    assert slots_from_order([7, 3, 9]) == {7: 1, 3: 2, 9: 3}


def test_slots_from_order_stops_at_the_sixth():
    slots = slots_from_order(list(range(1, 10)))
    assert len(slots) == AI_BAR_SLOTS
    assert 7 not in slots


def test_slots_from_order_rejects_duplicates():
    with pytest.raises(ValueError):
        slots_from_order([4, 4])


def test_claiming_a_taken_slot_pushes_the_other_off_the_bar():
    assert slots_after_claim({1: 3, 2: 4}, 9, 3) == {2: 4, 9: 3}


def test_claiming_moves_an_action_that_was_already_pinned():
    assert slots_after_claim({1: 2, 5: 6}, 1, 6) == {1: 6}


def test_claiming_none_unpins():
    assert slots_after_claim({1: 2, 5: 6}, 5, None) == {1: 2}


def test_slot_out_of_range_is_rejected():
    with pytest.raises(ValueError):
        slots_after_claim({}, 1, 0)
    with pytest.raises(ValueError):
        slots_after_claim({}, 1, AI_BAR_SLOTS + 1)


def test_run_scope_prefers_what_is_open_over_the_saved_scope():
    stored = {"topic_ids": [1]}
    assert run_scope(stored, {"topic_ids": [9], "file_ids": [4]}) == {
        "topic_ids": [9],
        "file_ids": [4],
    }


def test_run_scope_falls_back_to_the_saved_scope_for_the_scheduler():
    assert run_scope({"topic_ids": [1]}, None) == {"topic_ids": [1]}
    assert run_scope({"topic_ids": [1]}, {}) == {"topic_ids": [1]}
    assert run_scope(None, None) == {}


def test_first_free_slot_fills_gaps_then_gives_up():
    assert first_free_slot({1: 1, 2: 3}) == 2
    assert first_free_slot({}) == 1
    full = {i: i for i in range(1, AI_BAR_SLOTS + 1)}
    assert first_free_slot(full) is None
