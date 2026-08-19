"""Guards for user-defined topic types — inspect models and route source."""

import ast
import inspect
import textwrap

from areas.files.routes import topic_types as type_routes
from areas.files.routes import topics as topics_routes
from areas.files.services.document_marker_text import (
    iter_embed_pointers,
    wrap_editor_text,
)
from areas.files.services.template_slots import slot_key_from_name
from models import AiAction, Topic, TopicType
from shared import bootstrap


def test_topic_type_table_shape():
    columns = {c.name for c in TopicType.__table__.columns}
    assert {
        "id",
        "workspace_id",
        "name",
        "name_he",
        "order_index",
        "template_topic_id",
    } <= columns


def test_topic_carries_its_type():
    assert "topic_type_id" in Topic.__table__.columns
    assert "topic_type_id" in inspect.getsource(Topic.to_dict)


def test_ai_action_can_be_typed():
    assert "topic_type_id" in AiAction.__table__.columns
    assert "topic_type_id" in inspect.getsource(AiAction.to_dict)


def test_create_topic_accepts_a_type_and_a_clone():
    source = inspect.getsource(topics_routes.create_topic)
    assert "topic_type_id" in source
    assert "clone_from_topic_id" in source
    assert "clone_topic_skeleton" in source


def test_changing_type_does_not_reapply_the_template():
    source = inspect.getsource(topics_routes.update_topic)
    assert "clone_topic_skeleton" not in source
    assert "topic_type_id" in source


def test_type_routes_exist():
    source = inspect.getsource(type_routes)
    assert '"/topic-types"' in source
    assert "stamp_template_slots" in source


def test_create_type_requires_english_and_hebrew_names():
    source = inspect.getsource(type_routes.create_topic_type)
    assert "name_he" in source
    assert "english and hebrew names are required" in source


def test_bootstrap_does_not_seed_classification_tags():
    source = inspect.getsource(bootstrap.bootstrap_if_empty)
    assert "project" not in source
    assert "process" not in source


def test_empty_or_hebrew_file_names_still_get_a_slot_key():
    assert slot_key_from_name("Doc", file_id=9) == "doc"
    assert slot_key_from_name("Weekly Plan", file_id=9) == "weekly-plan"
    assert slot_key_from_name("מסמך", file_id=12) == "file-12"
    assert slot_key_from_name("   ", file_id=4) == "file-4"


def test_pointers_are_walked_in_document_order():
    body = wrap_editor_text('[TABLE id="3"]\n\nHello\n\n[TASK_LIST id="8"]')
    assert list(iter_embed_pointers(body)) == [("table", 3), ("task_list", 8)]


def test_topic_types_blueprint_is_registered():
    from areas import register_blueprints

    tree = ast.parse(textwrap.dedent(inspect.getsource(register_blueprints)))
    names = []
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom) and node.module == "areas.files.routes.topic_types":
            names.extend(alias.name for alias in node.names)
    assert "topic_types_bp" in names
