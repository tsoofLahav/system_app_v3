"""Pick a single emoji that matches highlighted text."""

from __future__ import annotations

import re

from services.openai_service import chat_text

_EMOJI_RE = re.compile(
    r"(\U0001F1E6-\U0001F1FF\U0001F3FB-\U0001F3FF"
    r"\U0001F900-\U0001F9FF"
    r"\U00002600-\U000026FF"
    r"\U00002700-\U000027BF"
    r"\U0001F300-\U0001FAFF"
    r"\U0001F600-\U0001F64F"
    r"\U0000231A-\U0000231B"
    r"\U000023E9-\U000023F3"
    r"\U000023F8-\U000023FA"
    r"\U000025AA-\U000025AB"
    r"\U000025B6"
    r"\U000025C0"
    r"\U000025FB-\U000025FE"
    r"\U00002614-\U00002615"
    r"\U00002648-\U00002653"
    r"\U00002668"
    r"\U00002693"
    r"\U000026A1"
    r"\U000026BD-\U000026BE"
    r"\U000026C4-\U000026C5"
    r"\U000026CE"
    r"\U000026D4"
    r"\U000026EA"
    r"\U000026F2-\U000026F3"
    r"\U000026F5"
    r"\U000026FA"
    r"\U000026FD"
    r"\U00002705"
    r"\U0000270A-\U0000270B"
    r"\U00002728"
    r"\U0000274C"
    r"\U0000274E"
    r"\U00002753-\U00002755"
    r"\U00002757"
    r"\U00002795-\U00002797"
    r"\U000027B0"
    r"\U000027BF"
    r"\U00002934-\U00002935"
    r"\U00002B05-\U00002B07"
    r"\U00002B1B-\U00002B1C"
    r"\U00003030"
    r"\U0000303D"
    r"\U00003297"
    r"\U00003299"
    r"\U0001F004"
    r"\U0001F0CF"
    r"\U0001F170-\U0001F171"
    r"\U0001F17E-\U0001F17F"
    r"\U0001F18E"
    r"\U0001F191-\U0001F19A"
    r"\U0001F201-\U0001F202"
    r"\U0001F21A"
    r"\U0001F22F"
    r"\U0001F232-\U0001F23A"
    r"\U0001F250-\U0001F251"
    r"\U0001F300-\U0001F5FF"
    r"\U0001F680-\U0001F6FF"
    r"\U0001F910-\U0001F96B"
    r"\U0001F980-\U0001F991"
    r"\U0000200D"
    r"\U0000FE0F"
    r")+"
)


def _first_emoji(value: str) -> str | None:
    match = _EMOJI_RE.search(value)
    if match:
        return match.group(0)
    stripped = value.strip()
    if not stripped:
        return None
    return stripped[0]


def run_suggest_emoji(*, text: str, locale: str = "en") -> dict:
    lang_note = "Prefer commonly understood emoji." if locale == "en" else "Prefer emoji that read clearly in Hebrew context."
    raw = chat_text(
        "You choose exactly one emoji that best matches the user's text. "
        "Reply with only that emoji — no words, labels, or punctuation. "
        f"{lang_note}",
        text.strip(),
        max_tokens=16,
    )
    emoji = _first_emoji(raw)
    if not emoji:
        raise ValueError("Could not pick an emoji")
    return {
        "tool": "suggest_emoji",
        "action": "insert",
        "result": emoji,
    }
