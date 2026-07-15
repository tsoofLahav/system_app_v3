from services.automation_definitions import (
    eager_companion_trigger_task,
    get_definition,
    rule_uses_shared_companion_trigger_task,
)


def test_project_update_is_not_eager_companion_trigger():
    definition = get_definition("project_update")
    assert definition is not None
    assert eager_companion_trigger_task(definition) is False


def test_project_update_does_not_use_shared_companion_trigger():
    class _Rule:
        key = "project_update"
        action_type = "project_update"
        trigger_type = "event"

    assert rule_uses_shared_companion_trigger_task(_Rule()) is False


def test_process_refresh_uses_shared_companion_trigger():
    class _Rule:
        key = "process_refresh"
        action_type = "process_refresh"
        trigger_type = "schedule"

    assert rule_uses_shared_companion_trigger_task(_Rule()) is True


def test_process_refresh_is_eager_companion_trigger():
    definition = get_definition("process_refresh")
    assert definition is not None
    assert eager_companion_trigger_task(definition) is True


def test_project_update_default_params_omit_section_name():
    definition = get_definition("project_update")
    assert definition is not None
    assert definition.companion is not None
    assert definition.companion.default_section_name == ""
