"""Which saved AI actions sit on the AI bar, and in what order.

`bar_slot` is 1..6 for the ones the user put on the bar and NULL for the rest,
which live in the actions menu only. The bar is small on purpose: six is what
fits beside the other bottom-bar tools without pushing the agent button off
screen.

The functions here work on plain `{action_id: slot}` maps so the rules can be
read (and tested) without a database.
"""

AI_BAR_SLOTS = 6


def slots_from_order(ordered_ids) -> dict[int, int]:
    """Ids in bar order → `{id: slot}`, numbered from 1. Anything past the
    sixth stays off the bar."""
    ids = [int(i) for i in ordered_ids]
    if len(set(ids)) != len(ids):
        raise ValueError("duplicate action ids")
    return {action_id: slot for slot, action_id in enumerate(ids[:AI_BAR_SLOTS], 1)}


def slots_after_claim(slots: dict[int, int], action_id: int, slot) -> dict[int, int]:
    """One action takes a slot, and whoever held it goes back to the menu.

    Losing the slot rather than being shuffled along keeps the other five where
    the user's hands expect them — a slot is also a keyboard shortcut.
    """
    action_id = int(action_id)
    if slot is None:
        return {k: v for k, v in slots.items() if k != action_id}

    slot = int(slot)
    if not 1 <= slot <= AI_BAR_SLOTS:
        raise ValueError(f"bar_slot must be between 1 and {AI_BAR_SLOTS}")
    kept = {k: v for k, v in slots.items() if k != action_id and v != slot}
    kept[action_id] = slot
    return kept


def first_free_slot(slots: dict[int, int]) -> int | None:
    """The lowest slot nobody holds, or None when the bar is full."""
    taken = set(slots.values())
    for slot in range(1, AI_BAR_SLOTS + 1):
        if slot not in taken:
            return slot
    return None
