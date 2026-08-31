"""Which saved AI actions sit on the AI bar, and in what order.

The bar is eight spots counting the agent as the first: ⌘1 is the agent,
⌘2…⌘8 are fixed saved-action seats 1..7 (unique per workspace among actions
that are not topic-scoped). They stay in the same place so each seat can be
a keyboard shortcut.

Topic-scoped actions do not take those seats. Each topic may have at most two
of them; they occupy extra seats 9 and 10 **only on that topic** (⌘9 / ⌘0).
Another topic can reuse 9 and 10 for its own pair. NULL still means the
actions menu.

The functions here work on plain `{action_id: slot}` maps so the rules can be
read (and tested) without a database.
"""

AI_BAR_SLOTS = 7
AI_TOPIC_EXTRA_COUNT = 2
AI_TOPIC_EXTRA_FIRST = 9
AI_TOPIC_EXTRA_LAST = AI_TOPIC_EXTRA_FIRST + AI_TOPIC_EXTRA_COUNT - 1
AI_TOPIC_ACTIONS_PER_TOPIC = 2


def is_fixed_slot(slot: int) -> bool:
    return 1 <= int(slot) <= AI_BAR_SLOTS


def is_topic_extra_slot(slot: int) -> bool:
    return AI_TOPIC_EXTRA_FIRST <= int(slot) <= AI_TOPIC_EXTRA_LAST


def slots_from_order(ordered_ids) -> dict[int, int]:
    """Ids in bar order → `{id: slot}`, numbered from 1. Anything past the
    seventh stays off the fixed bar."""
    ids = [int(i) for i in ordered_ids]
    if len(set(ids)) != len(ids):
        raise ValueError("duplicate action ids")
    return {action_id: slot for slot, action_id in enumerate(ids[:AI_BAR_SLOTS], 1)}


def slots_after_claim(slots: dict[int, int], action_id: int, slot) -> dict[int, int]:
    """One action takes a fixed seat, and whoever held it goes back to the menu.

    Losing the slot rather than being shuffled along keeps the other seats where
    the user's hands expect them — a slot is also a keyboard shortcut.
    """
    action_id = int(action_id)
    if slot is None:
        return {k: v for k, v in slots.items() if k != action_id}

    slot = int(slot)
    if not is_fixed_slot(slot):
        raise ValueError(f"bar_slot must be between 1 and {AI_BAR_SLOTS}")
    kept = {k: v for k, v in slots.items() if k != action_id and v != slot}
    kept[action_id] = slot
    return kept


def topic_extra_after_claim(
    slots: dict[int, int], action_id: int, slot
) -> dict[int, int]:
    """Same claim rule, for extra seats 9–10 on one topic."""
    action_id = int(action_id)
    if slot is None:
        return {k: v for k, v in slots.items() if k != action_id}

    slot = int(slot)
    if not is_topic_extra_slot(slot):
        raise ValueError(
            f"topic extra bar_slot must be {AI_TOPIC_EXTRA_FIRST} or {AI_TOPIC_EXTRA_LAST}"
        )
    kept = {k: v for k, v in slots.items() if k != action_id and v != slot}
    kept[action_id] = slot
    return kept


def first_free_slot(slots: dict[int, int]) -> int | None:
    """The lowest fixed slot nobody holds, or None when the bar is full."""
    taken = set(slots.values())
    for slot in range(1, AI_BAR_SLOTS + 1):
        if slot not in taken:
            return slot
    return None


def first_free_topic_extra(slots: dict[int, int]) -> int | None:
    taken = set(slots.values())
    for slot in range(AI_TOPIC_EXTRA_FIRST, AI_TOPIC_EXTRA_LAST + 1):
        if slot not in taken:
            return slot
    return None
