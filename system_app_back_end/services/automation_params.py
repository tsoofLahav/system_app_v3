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
    "merge_rule_params",
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


def merge_rule_params(existing, incoming):
    """Merge a partial params patch into stored params without dropping filled defaults."""
    base = copy.deepcopy(existing or {})
    if not incoming:
        return base

    patch = dict(incoming)
    merged = dict(base)

    for key, value in patch.items():
        if key in {
            "trigger",
            "companion_task",
            "scope",
            "bindings",
            "recap",
            "project_summary",
            "change_trigger",
            "view_resets",
        }:
            continue
        merged[key] = value

    if isinstance(patch.get("scope"), dict):
        scope = dict(base.get("scope") or {})
        scope.update(patch["scope"])
        merged["scope"] = scope

    if isinstance(patch.get("bindings"), dict):
        bindings = dict(base.get("bindings") or {})
        patch_bindings = patch["bindings"]
        if isinstance(patch_bindings.get("files"), list):
            patch_files = patch_bindings["files"]
            if patch_files:
                bindings["files"] = [dict(binding) for binding in patch_files]
            elif not bindings.get("files"):
                bindings["files"] = []
        merged["bindings"] = bindings

    if isinstance(patch.get("trigger"), dict):
        trigger = dict(base.get("trigger") or {})
        trigger.update(patch["trigger"])
        merged["trigger"] = trigger

    if isinstance(patch.get("companion_task"), dict):
        companion = dict(base.get("companion_task") or {})
        companion.update(patch["companion_task"])
        merged["companion_task"] = companion

    if isinstance(patch.get("recap"), dict):
        recap = dict(base.get("recap") or {})
        recap.update(patch["recap"])
        merged["recap"] = recap

    if isinstance(patch.get("project_summary"), dict):
        project_summary = dict(base.get("project_summary") or {})
        project_summary.update(patch["project_summary"])
        merged["project_summary"] = project_summary

    if isinstance(patch.get("change_trigger"), dict):
        change_trigger = dict(base.get("change_trigger") or {})
        change_trigger.update(patch["change_trigger"])
        merged["change_trigger"] = change_trigger

    if isinstance(patch.get("view_resets"), dict):
        view_resets = {
            view_type: dict(config)
            for view_type, config in (base.get("view_resets") or {}).items()
            if isinstance(config, dict)
        }
        for view_type, config in patch["view_resets"].items():
            if not isinstance(config, dict):
                continue
            reset_config = dict(view_resets.get(view_type) or {})
            reset_config.update(config)
            view_resets[view_type] = reset_config
        merged["view_resets"] = view_resets

    return merged


def persist_rule_params(rule, params):
    """Assign params and force SQLAlchemy to persist JSONB changes."""
    normalized = apply_definition_to_params(params, rule.key, rule.action_type)
    rule.params = copy.deepcopy(normalized)
    flag_modified(rule, "params")


def finalize_rule_params(rule):
    """Persist a fully hydrated params object after merge or create."""
    rule.params = copy.deepcopy(
        apply_definition_to_params(rule.params, rule.key, rule.action_type),
    )
    flag_modified(rule, "params")
