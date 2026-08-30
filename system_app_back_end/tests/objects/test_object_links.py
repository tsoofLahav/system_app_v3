"""Description = host → info; related = info ↔ info only."""

import inspect

from areas.objects.routes import objects as object_routes
from areas.objects.services.object_graph import (
    normalize_description_anchor,
    related_requires_info,
)


def test_normalize_description_anchor_requires_segment_and_range():
    out = normalize_description_anchor(
        {"segment_id": "b1#infoText", "start": 2, "end": 9, "file_id": 4}
    )
    assert out == {
        "segment_id": "b1#infoText",
        "start": 2,
        "end": 9,
        "file_id": 4,
    }


def test_normalize_description_anchor_rejects_bad_ranges():
    try:
        normalize_description_anchor({"segment_id": "a", "start": 4, "end": 4})
        assert False, "expected ValueError"
    except ValueError as err:
        assert "end" in str(err)


def test_normalize_description_anchor_rejects_missing_segment():
    try:
        normalize_description_anchor({"start": 0, "end": 3, "file_id": 1})
        assert False, "expected ValueError"
    except ValueError as err:
        assert "segment_id" in str(err)


def test_related_requires_info_endpoints():
    assert related_requires_info("info", "info")
    assert not related_requires_info("task_list", "info")
    assert not related_requires_info("info", "table")
    assert not related_requires_info("task_list", "table")


def test_description_create_is_host_to_info():
    source = inspect.getsource(object_routes.create_object_link)
    assert "description links require an info source" not in source
    assert "anchor.file_id required for description" not in source
    assert "description links require an info target" in source
    assert "normalize_description_anchor" in source
    assert "related links require info endpoints" in source
    assert "find_related_link" in source
    # Many description spans per host: description rows are always inserted.
    desc_branch = source.split('if kind == "description":', 1)[1].split(
        "# related:", 1
    )[0]
    assert "db.session.add(link)" in desc_branch
    assert "existing" not in desc_branch


def test_patch_description_anchor_updates_span():
    source = inspect.getsource(object_routes.patch_object_link)
    assert "patch_description_anchor" in source
    from areas.objects.routes import tasks as task_routes

    task_source = inspect.getsource(task_routes.patch_task_description_link)
    assert "patch_description_anchor" in task_source
    from areas.objects.services import object_graph

    helper = inspect.getsource(object_graph.patch_description_anchor)
    assert "only description anchors can be patched" in helper


def test_info_host_description_does_not_write_related():
    source = inspect.getsource(object_routes.create_object_link)
    desc_branch = source.split('if kind == "description":', 1)[1].split(
        "# related:", 1
    )[0]
    assert "ensure_related_info_link" not in desc_branch


def test_patch_allows_info_payload():
    source = inspect.getsource(object_routes.update_object)
    assert 'embed.type in {"image", "table", "info"}' in source


def test_file_description_links_use_host_file():
    source = inspect.getsource(object_routes.list_file_description_links)
    assert 'target_type="file"' not in source
    assert "description_links_hosted_in_file" in source
    assert "info_peer_dict" in source


def test_task_payload_includes_description_links():
    from models import Task

    dumped = inspect.getsource(Task.to_dict)
    assert "description_links" in dumped
    assert "description_link_dicts_for_task" in dumped


def test_task_description_link_create_path():
    from areas.objects.routes import tasks as task_routes

    source = inspect.getsource(task_routes.create_task_description_link)
    assert "TASK_LINK_TYPE" in source
    assert "description links require an info target" in source
    assert "normalize_description_anchor" in source
    assert 'source_type=TASK_LINK_TYPE' in source
    assert "task links must be kind=description" in source


def test_file_description_links_include_task_hosts():
    from areas.objects.services import object_graph

    source = inspect.getsource(object_graph.description_links_hosted_in_file)
    assert "TASK_LINK_TYPE" in source
    assert "task_list_id" in source


def test_delete_task_drops_task_links():
    from areas.objects.services import delete_cascade

    source = inspect.getsource(delete_cascade.delete_task_cascade)
    assert "delete_links_for_task" in source
    list_source = inspect.getsource(delete_cascade.delete_task_list_cascade)
    assert "delete_links_for_task" in list_source

