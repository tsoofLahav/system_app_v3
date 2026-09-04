"""Pick a live file by name, using the same resemblance as Connect-info search.

Dart twin: `info_pick_rank.dart` (`textSimilarity` / `similarNameThreshold`).
"""

from __future__ import annotations

import re

SIMILAR_NAME_THRESHOLD = 0.45

_ws = re.compile(r"\s+")


def normalize_comparable(value: str) -> str:
    return _ws.sub(" ", (value or "").strip().lower())


def text_similarity(a: str, b: str) -> float:
    left = normalize_comparable(a)
    right = normalize_comparable(b)
    if not left or not right:
        return 0.0
    if left == right:
        return 1.0
    if left in right or right in left:
        shorter = min(len(left), len(right))
        longer = max(len(left), len(right))
        return 0.72 + 0.27 * (shorter / longer)
    return _dice_bigrams(left, right)


def is_similar_name(probe: str, title: str) -> bool:
    return text_similarity(probe, title) >= SIMILAR_NAME_THRESHOLD


def _dice_bigrams(a: str, b: str) -> float:
    if len(a) < 2 or len(b) < 2:
        return 1.0 if a == b else 0.0
    left = _bigrams(a)
    right = _bigrams(b)
    if not left or not right:
        return 0.0
    used = [False] * len(right)
    overlap = 0
    for gram in left:
        for i, other in enumerate(right):
            if used[i] or other != gram:
                continue
            used[i] = True
            overlap += 1
            break
    return (2 * overlap) / (len(left) + len(right))


def _bigrams(value: str) -> list[str]:
    if len(value) < 2:
        return []
    return [value[i : i + 2] for i in range(len(value) - 1)]


def pick_closest_named(probe: str, files: list) -> object | None:
    """Closest live file at or above the threshold. Ties prefer the lower id."""
    best = None
    best_score = -1.0
    for file in files:
        score = text_similarity(probe, getattr(file, "name", None) or "")
        if score < SIMILAR_NAME_THRESHOLD:
            continue
        file_id = int(getattr(file, "id", 0) or 0)
        if score > best_score or (
            score == best_score and (best is None or file_id < int(best.id))
        ):
            best = file
            best_score = score
    return best


def named_file_error(probe: str) -> str:
    name = (probe or "").strip() or "that file"
    return f'no file close enough to “{name}”'
