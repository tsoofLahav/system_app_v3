import copy

from sqlalchemy.orm.attributes import flag_modified

PARAMS_VERSION = 2

DEFAULT_COMPANION = {
    "weekly_process_refresh": {
        "enabled": True,
        "view_type": "daily",
        "section_name": "Process updates",
        "flow_key": "process_update_review",
        "title_template": "Review update: {topic_name}",
    },
}


def normalize_params(params, rule_key=None, action_type=None):
    raw = dict(params or {})
    if raw.get("version") == PARAMS_VERSION:
        normalized = raw
    else:
        normalized = _migrate_v1_params(raw, rule_key, action_type)
    if rule_key == "weekly_process_refresh" or action_type == "weekly_process_refresh":
        return _ensure_weekly_process_refresh_params(normalized)
    return normalized


def _ensure_weekly_process_refresh_params(params):
    result = dict(params)
    result.setdefault("version", PARAMS_VERSION)
    scope = dict(result.get("scope") or {})
    if scope.get("kind") not in {"topic_type", "topic"}:
        scope = {"kind": "topic_type", "topic_type": "process"}
    elif scope.get("kind") == "topic_type":
        scope.setdefault("topic_type", "process")
    result["scope"] = scope
    bindings = result.get("bindings") or {}
    if not bindings.get("files"):
        result["bindings"] = {
            "files": [
                {"role": "plan", "match": {"type": "plan"}},
                {"role": "doc", "match": {"type": "doc"}},
                {"role": "tasks", "match": {"type": "tasks"}},
            ],
        }
    if not result.get("companion_task"):
        result["companion_task"] = DEFAULT_COMPANION["weekly_process_refresh"]
    return result


def _migrate_v1_params(params, rule_key, action_type):
    if rule_key == "daily_rotation":
        return {
            "version": PARAMS_VERSION,
            "scope": {
                "kind": "topic",
                "topic_name": params.get("topic_name", "main"),
            },
            "bindings": {
                "files": [
                    {
                        "role": "daily",
                        "match": {
                            "type": params.get("type", "main"),
                            "name": params.get("name", "Daily"),
                        },
                    }
                ],
            },
            "companion_task": None,
            "topic_name": params.get("topic_name", "main"),
            "name": params.get("name", "Daily"),
            "type": params.get("type", "main"),
        }

    if rule_key == "weekly_process_refresh" or action_type == "weekly_process_refresh":
        return {
            "version": PARAMS_VERSION,
            "scope": {"kind": "topic_type", "topic_type": "process"},
            "bindings": {
                "files": [
                    {"role": "plan", "match": {"type": "plan"}},
                    {"role": "doc", "match": {"type": "doc"}},
                    {"role": "tasks", "match": {"type": "tasks"}},
                ],
            },
            "companion_task": DEFAULT_COMPANION["weekly_process_refresh"],
        }

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
    rule.params = copy.deepcopy(params)
    flag_modified(rule, "params")
