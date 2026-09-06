"""Inner checklist lines on an info body, and the outer-task sync hooks."""

import inspect

from areas.objects.services import inner_tasks
from areas.objects.services import task_ops
from areas.objects.routes import information as information_routes
from areas.objects.services.task_list_order import move_task_to_list
from areas.files.services import document_agent_text


def test_parse_and_unanimous():
    body = "- [ ] one\nkeep prose\n- [x] two"
    items = inner_tasks.parse_inner_task_lines(body)
    assert [item.title for item in items] == ["one", "two"]
    assert [item.done for item in items] == [False, True]
    assert inner_tasks.inner_tasks_unanimous(body) is None
    assert inner_tasks.inner_tasks_unanimous("- [x] a\n- [x] b") is True
    assert inner_tasks.inner_tasks_unanimous("- [ ] a\n- [ ] b") is False
    assert inner_tasks.inner_tasks_unanimous("just prose") is None


def test_set_all_and_toggle_keep_prose():
    body = "note\n- [ ] one\n- [x] two"
    done = inner_tasks.set_all_inner_tasks(body, done=True)
    assert done == "note\n☑ one\n☑ two"
    active = inner_tasks.set_all_inner_tasks(done, done=False)
    assert active == "note\n☐ one\n☐ two"
    items = inner_tasks.parse_inner_task_lines(body)
    flipped = inner_tasks.toggle_inner_task_at(body, items[0].mark_start)
    assert flipped == "note\n☑ one\n- [x] two"


def test_parse_glyph_without_dash():
    items = inner_tasks.parse_inner_task_lines("☐ milk\n☑ eggs")
    assert [item.title for item in items] == ["milk", "eggs"]
    assert [item.done for item in items] == [False, True]


def test_status_writes_sync_inner_tasks():
    source = inspect.getsource(task_ops.set_task_status)
    assert "sync_inner_tasks_from_outer" in source
    move = inspect.getsource(move_task_to_list)
    assert "sync_inner_tasks_from_outer" in move


def test_info_writes_sync_outer_tasks():
    patch = inspect.getsource(information_routes.update_information)
    assert "sync_outer_tasks_from_info" in patch
    agent = inspect.getsource(document_agent_text._sync_info)
    assert "sync_outer_tasks_from_info" in agent
