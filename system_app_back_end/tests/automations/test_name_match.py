from types import SimpleNamespace

from areas.automations.services.name_match import (
    is_similar_name,
    named_file_error,
    pick_closest_named,
    text_similarity,
)


def test_same_name_is_exact():
    assert text_similarity("Milk", "Milk") == 1
    assert is_similar_name("Buy milk", "Milk") is True
    assert is_similar_name("Project plan", "totally other") is False


def test_pick_closest_prefers_exact_then_similar():
    files = [
        SimpleNamespace(id=9, name="Zebra"),
        SimpleNamespace(id=2, name="Milk"),
        SimpleNamespace(id=3, name="Buy milk list"),
    ]
    assert pick_closest_named("Milk", files).id == 2
    assert pick_closest_named("Daily notes", files) is None


def test_nothing_close_enough_names_the_probe():
    assert "Daily" in named_file_error("Daily")


def test_legacy_missing_id_has_no_match_without_a_name():
    files = [SimpleNamespace(id=1, name="Inbox")]
    assert pick_closest_named("", files) is None
