import copy

from sqlalchemy.orm.attributes import flag_modified

from services.automation_definitions import (
    PARAMS_VERSION,
    apply_definition_to_params,
    default_params,
    get_definition,
)

__all__ = [
    "PARAMS_VERSION",
    "normalize_params",
    "params_v2_for_rule",
    "scope_kind",
    "binding_files",
    "companion_config",
    "trigger_config",
    "rule_params_snapshot",
    "persist_rule_params",
    "default_params",
    "get_definition",
]


def normalize_params(params, rule_key=None, action_type=None):
    raw = dict(params or {})
    if raw.get("version") != PARAMS_VERSION:
        raw = _migrate_v1_params(raw, rule_key, action_type)
    return apply_definition_to_params(raw, rule_key, action_type)


def _migrate_v1_params(params, rule_key, action_type):
    definition = get_definition(rule_key, action_type)
    if definition is not None:
        migrated = default_params(definition.key)
        migrated.update(
            {
                key: value
                for key, value in params.items()
                if key not in {"scope", "bindings", "companion_task", "version"}
            }
        )
        return migrated

    return {
        "version": PARAMS_VERSION,
        "scope": params.get("scope") or {"kind": "all"},
        "bindings": params.get("bindings") or {"files": []},
        "companion_task": params.get("companion_task"),
        **{
            key: value
            for key, value in params.items()
            if key not in {"scope", "bindings", "companion_task", "version"}
        },
    }


def params_v2_for_rule(rule_key, action_type):
    return normalize_params({}, rule_key, action_type)


def scope_kind(params):
    return (params.get("scope") or {}).get("kind", "all")


def binding_files(params):
    bindings = params.get("bindings") or {}
    return bindings.get("files") or []


def companion_config(params):
    return params.get("companion_task")


def trigger_config(params):
    return params.get("trigger")


def rule_params_snapshot(rule):
    """Detached deep copy of rule params safe to mutate without touching the ORM object."""
    return copy.deepcopy(normalize_params(rule.params, rule.key, rule.action_type))


def persist_rule_params(rule, params):
    """Assign params and force SQLAlchemy to persist JSONB changes."""
    normalized = apply_definition_to_params(params, rule.key, rule.action_type)
    rule.params = copy.deepcopy(normalized)
    flag_modified(rule, "params")


def finalize_rule_params(rule):
    """Ensure version and missing defaults without overwriting stored scope/bindings."""
    rule.params = apply_definition_to_params(rule.params, rule.key, rule.action_type)
    flag_modified(rule, "params")
