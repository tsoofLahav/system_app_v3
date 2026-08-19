"""Scope: what an automation may touch, and where placeless steps land."""

from unittest.mock import patch

from areas.automations.services.scope import describe, resolve_scope, target_topic_id


def test_one_topic_resolves_to_that_topic():
    assert resolve_scope({"kind": "topic", "topic_id": 3}, workspace_id=1) == {
        "workspace_id": 1,
        "topic_ids": [3],
    }


def test_a_topic_type_resolves_through_the_type_id():
    with patch(
        "areas.automations.services.scope.topic_ids_for_type", return_value=[4, 9]
    ):
        resolved = resolve_scope(
            {"kind": "topic_type", "topic_type_id": 2}, workspace_id=1
        )
    assert resolved == {"workspace_id": 1, "topic_ids": [4, 9]}


def test_a_topic_type_still_reads_the_old_tag_name():
    with patch(
        "areas.automations.services.scope.topic_ids_for_tag", return_value=[4, 9]
    ):
        resolved = resolve_scope(
            {"kind": "topic_type", "tag": "process"}, workspace_id=1
        )
    assert resolved == {"workspace_id": 1, "topic_ids": [4, 9]}


def test_all_is_the_workspace_and_nothing_narrower():
    assert resolve_scope({"kind": "all"}, workspace_id=2) == {"workspace_id": 2}


def test_rows_written_before_the_kinds_existed_still_resolve():
    assert resolve_scope({"topic_ids": [5], "file_ids": [7]}, workspace_id=1) == {
        "workspace_id": 1,
        "topic_ids": [5],
        "file_ids": [7],
    }


def test_a_single_topic_is_a_destination():
    assert target_topic_id({"workspace_id": 1, "topic_ids": [3]}) == 3


def test_several_topics_are_not_a_destination():
    """"Somewhere in these five" is not a place to put a new file."""
    assert target_topic_id({"workspace_id": 1, "topic_ids": [3, 4]}) is None
    assert target_topic_id({"workspace_id": 1}) is None


def test_describe_reads_like_a_sentence():
    assert describe({"kind": "topic", "topic_id": 3}) == "topic 3"
    assert (
        describe({"kind": "topic_type", "topic_type_id": 2}) == "topics of type 2"
    )
    assert describe({"kind": "topic_type", "tag": "process"}) == "topics tagged 'process'"
    assert describe({}) == "the whole workspace"
