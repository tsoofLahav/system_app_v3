"""Pick one or two emojis that match highlighted text."""

from __future__ import annotations

import re

from services.openai_service import chat_text

_EMOJI_BASE_CLASS = (
    r"\U0001F1E6-\U0001F1FF"
    r"\U0001F300-\U0001FAFF"
    r"\U0001F600-\U0001F64F"
    r"\U0001F680-\U0001F6FF"
    r"\U0001F900-\U0001F9FF"
    r"\U00002600-\U000026FF"
    r"\U00002700-\U000027BF"
    r"\U0000231A-\U0000231B"
    r"\U000023E9-\U000023F3"
    r"\U000023F8-\U000023FA"
    r"\U000025AA-\U000025AB"
    r"\U000025B6"
    r"\U000025C0"
    r"\U000025FB-\U000025FE"
    r"\U00003297"
    r"\U00003299"
)

_EMOJI_ONE = re.compile(
    rf"(?:[{_EMOJI_BASE_CLASS}])"
    rf"(?:(?:[\U0001F3FB-\U0001F3FF]|\U0000FE0F|\U0000200D(?:[{_EMOJI_BASE_CLASS}])))*"
)


def _is_regional_indicator(code: int) -> bool:
    return 0x1F1E6 <= code <= 0x1F1FF


def _extract_emojis(value: str, *, max_count: int = 2) -> str | None:
    tokens: list[str] = []
    i = 0
    text = value.strip()
    while i < len(text) and len(tokens) < max_count:
        while i < len(text) and text[i].isspace():
            i += 1
        if i >= len(text):
            break

        if i + 1 < len(text):
            first = ord(text[i])
            second = ord(text[i + 1])
            if _is_regional_indicator(first) and _is_regional_indicator(second):
                tokens.append(text[i : i + 2])
                i += 2
                continue

        match = _EMOJI_ONE.match(text, i)
        if not match:
            break
        tokens.append(match.group(0))
        i = match.end()

    if not tokens:
        return None
    return "".join(tokens)


def run_suggest_emoji(*, text: str, locale: str = "en") -> dict:
    lang_note = (
        "Prefer commonly understood emoji."
        if locale == "en"
        else "Prefer emoji that read clearly in Hebrew context."
    )
    raw = chat_text(
        "You choose emoji that best match the user's text. "
        "Reply with one emoji by default. "
        "Use two emojis only when the meaning is clearly better as a pair "
        "(for example sun and rain, or pizza and beer). "
        "Never use more than two emojis. "
        "Reply with only the emoji(s) — no words, labels, or punctuation. "
        f"{lang_note}",
        text.strip(),
        max_tokens=24,
    )
    emoji = _extract_emojis(raw)
    if not emoji:
        raise ValueError("Could not pick an emoji")
    return {
        "tool": "suggest_emoji",
        "action": "insert",
        "result": emoji,
    }
