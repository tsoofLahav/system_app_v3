"""Tests for project update automation helpers."""

from types import SimpleNamespace

from services.automation_dispatcher import file_qualifies_as_moved_to_additional
from services.ai_project_update_actions import build_project_update_change_set
from services.diff_engine import build_doc_row_change_set


def _file(file_id, name, file_type):
    return SimpleNamespace(id=file_id, name=name, type=file_type)


def test_build_doc_row_change_set_adds_row_change():
    units = [
        {
            "id": "table:1:row:0",
            "kind": "table_row",
            "text": "Date | Entry",
        }
    ]
    doc = build_doc_row_change_set(
        "doc",
        "Documentation",
        units,
        [{"date": "2026-07-06", "text": "Shipped first milestone"}],
    )

    assert doc["key"] == "doc"
    assert len(doc["changes"]) == 1
    change = doc["changes"][0]
    assert change["action"] == "add_row"
    assert change["row_date"] == "2026-07-06"
    assert change["row_text"] == "Shipped first milestone"


def test_build_doc_row_change_set_creates_anchor_when_empty():
    doc = build_doc_row_change_set(
        "doc",
        "Documentation",
        [],
        [{"date": "2026-07-06", "text": "First entry"}],
    )

    assert len(doc["units"]) == 1
    assert doc["units"][0]["id"] == "doc:table:anchor"
    assert len(doc["changes"]) == 1


def test_build_project_update_change_set_includes_only_non_empty_documents(monkeypatch):
    plan = _file(1, "Plan", "plan")
    execution = _file(2, "Execution", "execution")
    tasks = _file(3, "Tasks", "tasks")
    doc = _file(4, "Documentation", "doc")

    monkeypatch.setattr(
        "services.ai_project_update_actions.units_from_file",
        lambda _file_id: [
            {
                "id": "block:9:item:0",
                "kind": "list_item",
                "text": "Existing point",
            }
        ],
    )
    change_set = build_project_update_change_set(
        plan,
        execution,
        tasks,
        [
            {
                "part_name": "API",
                "action": "update",
                "execution_ops": [
                    {
                        "op": "add_after",
                        "unit_id": "block:9:item:0",
                        "text": "Finalize API contract",
                    }
                ],
            }
        ],
    )

    keys = [document["key"] for document in change_set["documents"]]
    assert keys == ["execution"]
    execution_doc = change_set["documents"][0]
    assert execution_doc["changes"][0]["new_text"] == "Finalize API contract"
    assert execution_doc["changes"][0]["id"] == "execution:api:c1"


def test_file_qualifies_as_moved_to_additional_demotion(monkeypatch):
    topic = SimpleNamespace(type="project", archived_at=None)
    file = SimpleNamespace(
        type="text",
        is_main=False,
        topic_id=10,
    )

    monkeypatch.setattr(
        "services.automation_dispatcher.db.session.get",
        lambda _model, _id: topic,
    )

    assert file_qualifies_as_moved_to_additional(
        file,
        prev_is_main=True,
        prev_topic_id=10,
    )


def test_file_qualifies_as_moved_to_additional_rejects_create_in_additional(
    monkeypatch,
):
    topic = SimpleNamespace(type="project", archived_at=None)
    file = SimpleNamespace(type="text", is_main=False, topic_id=10)

    monkeypatch.setattr(
        "services.automation_dispatcher.db.session.get",
        lambda _model, _id: topic,
    )

    assert not file_qualifies_as_moved_to_additional(
        file,
        prev_is_main=False,
        prev_topic_id=10,
    )
