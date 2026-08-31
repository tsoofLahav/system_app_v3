"""Guards for bilingual AI-action / automation names and action scope."""

import inspect

from areas.automations.routes import automations as automation_routes
from areas.production_agent.routes import ai_actions as action_routes
from models import AiAction, Automation


def test_ai_action_has_hebrew_name_and_topic_scope():
    columns = {c.name for c in AiAction.__table__.columns}
    assert {"name_he", "topic_id", "topic_type_id"} <= columns
    dumped = inspect.getsource(AiAction.to_dict)
    assert "name_he" in dumped
    assert "topic_id" in dumped


def test_create_ai_action_requires_both_names():
    source = inspect.getsource(action_routes.create_ai_action)
    assert "name and name_he are required" in source
    patch = inspect.getsource(action_routes.update_ai_action)
    assert "name and name_he are required" in patch


def test_a_topic_may_only_have_two_specific_actions():
    source = inspect.getsource(action_routes.create_ai_action)
    assert "this topic already has 2 specific actions" in source
    patch = inspect.getsource(action_routes.update_ai_action)
    assert "this topic already has 2 specific actions" in patch


def test_ai_action_scope_is_topic_xor_type_xor_all():
    source = inspect.getsource(action_routes._apply_scope)
    assert "topic_id" in source
    assert "topic_type_id" in source
    assert "Topic wins if both sent" in source


def test_automation_has_hebrew_name():
    columns = {c.name for c in Automation.__table__.columns}
    assert "name_he" in columns
    assert "name_he" in inspect.getsource(Automation.to_dict)


def test_create_automation_requires_both_names():
    source = inspect.getsource(automation_routes.create_automation)
    assert "name and name_he are required" in source
    patch = inspect.getsource(automation_routes.update_automation)
    assert "name and name_he are required" in patch
