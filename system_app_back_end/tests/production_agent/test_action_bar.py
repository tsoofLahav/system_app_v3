"""Tests for AI bar slot rules (saved AI actions)."""

import pytest

from areas.production_agent.services.action_bar import (
    AI_BAR_SLOTS,
    AI_TOPIC_EXTRA_FIRST,
    AI_TOPIC_EXTRA_LAST,
    first_free_slot,
    first_free_topic_extra,
    slots_after_claim,
    slots_from_order,
    topic_extra_after_claim,
)


def test_slots_from_order_numbers_from_one():
    assert slots_from_order([7, 3, 9]) == {7: 1, 3: 2, 9: 3}


def test_slots_from_order_stops_at_the_seventh():
    slots = slots_from_order(list(range(1, 12)))
    assert len(slots) == AI_BAR_SLOTS
    assert 8 not in slots


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


def test_first_free_slot_fills_gaps_then_gives_up():
    assert first_free_slot({1: 1, 2: 3}) == 2
    assert first_free_slot({}) == 1
    full = {i: i for i in range(1, AI_BAR_SLOTS + 1)}
    assert first_free_slot(full) is None


def test_topic_extras_are_9_and_10_and_unique_per_topic_map():
    assert topic_extra_after_claim({}, 4, 9) == {4: 9}
    assert topic_extra_after_claim({4: 9}, 5, 10) == {4: 9, 5: 10}
    claimed = topic_extra_after_claim({4: 9}, 7, 9)
    assert claimed == {7: 9}
    with pytest.raises(ValueError):
        topic_extra_after_claim({}, 1, 1)


def test_first_free_topic_extra():
    assert first_free_topic_extra({}) == AI_TOPIC_EXTRA_FIRST
    assert first_free_topic_extra({1: 9}) == AI_TOPIC_EXTRA_LAST
    assert first_free_topic_extra({1: 9, 2: 10}) is None
