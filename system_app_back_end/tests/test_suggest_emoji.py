from services.ai_interactive.suggest_emoji import _extract_emojis


def test_extract_one_emoji():
    assert _extract_emojis("🔥") == "🔥"


def test_extract_two_emojis():
    assert _extract_emojis("🍕🍺") == "🍕🍺"
    assert _extract_emojis("☀️ 🌧️") == "☀️🌧️"


def test_caps_at_two_emojis():
    assert _extract_emojis("🎯✅🔥") == "🎯✅"


def test_keeps_zwj_sequence_as_one():
    assert _extract_emojis("👨‍💻") == "👨‍💻"


def test_ignores_trailing_text():
    assert _extract_emojis("🎯 done") == "🎯"


def test_keeps_variation_selector():
    assert _extract_emojis("☀️ 🌧️") == "☀️🌧️"
