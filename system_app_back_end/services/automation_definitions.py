"""Built-in automation definitions — single source of truth for scope, bindings, activations."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from services.automation_schedule import DEFAULT_AUTOMATION_TIMEZONE

PARAMS_VERSION = 2


@dataclass(frozen=True)
class ScopeConfig:
    fixed: dict[str, Any]
    allowed_kinds: tuple[str, ...] = ("topic_type", "topic", "all")


@dataclass(frozen=True)
class FileBinding:
    role: str
    match: dict[str, Any]


@dataclass(frozen=True)
class CompanionConfig:
    enabled: bool = True
    flow_key: str = "process_update_review"
    title_template: str = "Review update: {topic_name}"
    default_view_type: str = "daily"
    default_section_name: str = "Process updates"


DEFAULT_CHANGE_TRIGGER_IDLE_SECONDS = 30


@dataclass(frozen=True)
class ChangeTriggerConfig:
    """Idle debounce + in-run coalescing for event-driven automations."""

    enabled: bool = True
    idle_seconds: int = DEFAULT_CHANGE_TRIGGER_IDLE_SECONDS
    coalesce_during_run: bool = True


@dataclass(frozen=True)
class AiConfig:
    action_key: str | None = None
    proposal_types: tuple[str, ...] = ()
    review_documents: tuple[str, ...] = ()


@dataclass(frozen=True)
class AutomationDefinition:
    key: str
    name: str
    description: str
    action_type: str
    scope: ScopeConfig
    activations: tuple[str, ...]
    bindings: tuple[FileBinding, ...]
    companion: CompanionConfig | None = None
    ai: AiConfig | None = None
    timezone_default: str = DEFAULT_AUTOMATION_TIMEZONE
    fan_out: bool = True
    default_schedule: str | None = None
    default_enabled: bool = True
    change_trigger: ChangeTriggerConfig | None = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "key": self.key,
            "name": self.name,
            "description": self.description,
            "action_type": self.action_type,
            "scope": {
                "fixed": self.scope.fixed,
                "allowed_kinds": list(self.scope.allowed_kinds),
            },
            "activations": list(self.activations),
            "bindings": [
                {"role": binding.role, "match": dict(binding.match)}
                for binding in self.bindings
            ],
            "companion": _companion_to_dict(self.companion),
            "ai": _ai_to_dict(self.ai),
            "timezone_default": self.timezone_default,
            "fan_out": self.fan_out,
            "default_schedule": self.default_schedule,
            "default_enabled": self.default_enabled,
            "change_trigger": _change_trigger_to_dict(self.change_trigger),
            "default_params": default_params(self.key),
        }


def _change_trigger_to_dict(
    change_trigger: ChangeTriggerConfig | None,
) -> dict[str, Any] | None:
    if change_trigger is None:
        return None
    return {
        "enabled": change_trigger.enabled,
        "idle_seconds": change_trigger.idle_seconds,
        "coalesce_during_run": change_trigger.coalesce_during_run,
    }


def _companion_to_dict(companion: CompanionConfig | None) -> dict[str, Any] | None:
    if companion is None:
        return None
    return {
        "enabled": companion.enabled,
        "flow_key": companion.flow_key,
        "title_template": companion.title_template,
        "default_view_type": companion.default_view_type,
        "default_section_name": companion.default_section_name,
    }


def _ai_to_dict(ai: AiConfig | None) -> dict[str, Any] | None:
    if ai is None:
        return None
    return {
        "action_key": ai.action_key,
        "proposal_types": list(ai.proposal_types),
        "review_documents": list(ai.review_documents),
    }


AUTOMATION_DEFINITIONS: dict[str, AutomationDefinition] = {
    "daily_rotation": AutomationDefinition(
        key="daily_rotation",
        name="Daily rotation",
        description="Archive the current main Daily file and create a fresh one.",
        action_type="rotate_daily_main_file",
        scope=ScopeConfig(
            fixed={"kind": "topic", "topic_name": "main"},
            allowed_kinds=("topic", "all"),
        ),
        activations=("schedule",),
        bindings=(
            FileBinding(
                role="daily",
                match={"type": "main", "name": "Daily"},
            ),
        ),
        companion=None,
        ai=None,
        default_schedule="daily 00:00",
        default_enabled=True,
        fan_out=False,
    ),
    "process_refresh": AutomationDefinition(
        key="process_refresh",
        name="Update all processes",
        description=(
            "For each process topic, run a smart update on plan, doc, and tasks files."
        ),
        action_type="process_refresh",
        scope=ScopeConfig(
            fixed={"kind": "topic_type", "topic_type": "process"},
            allowed_kinds=("topic_type", "topic", "all"),
        ),
        activations=("schedule", "task"),
        bindings=(
            FileBinding(role="plan", match={"type": "plan"}),
            FileBinding(role="doc", match={"type": "doc"}),
            FileBinding(role="tasks", match={"type": "tasks"}),
        ),
        companion=CompanionConfig(
            enabled=True,
            flow_key="process_update_review",
            title_template="Review update: {topic_name}",
            default_view_type="daily",
            default_section_name="Process updates",
        ),
        ai=AiConfig(
            action_key="smart_process_update",
            proposal_types=("process_smart_update", "process_refresh_skipped"),
            review_documents=("plan", "tasks"),
        ),
        default_schedule="weekly mon 00:00",
        default_enabled=False,
        fan_out=True,
    ),
    "process_recap_update": AutomationDefinition(
        key="process_recap_update",
        name="Update process recap",
        description=(
            "When plan, documentation, or tasks change, regenerate the process "
            "recap with an AI summary and recent update notes."
        ),
        action_type="process_recap_update",
        scope=ScopeConfig(
            fixed={"kind": "topic_type", "topic_type": "process"},
            allowed_kinds=("topic_type", "topic", "all"),
        ),
        activations=("event",),
        bindings=(
            FileBinding(role="plan", match={"type": "plan"}),
            FileBinding(role="doc", match={"type": "doc"}),
            FileBinding(role="tasks", match={"type": "tasks"}),
            FileBinding(role="overview", match={"type": "overview"}),
        ),
        companion=None,
        ai=AiConfig(
            action_key="smart_process_recap_update",
            proposal_types=(),
            review_documents=(),
        ),
        default_schedule=None,
        default_enabled=True,
        fan_out=False,
        change_trigger=ChangeTriggerConfig(idle_seconds=30),
    ),
    "view_task_reset": AutomationDefinition(
        key="view_task_reset",
        name="Reset view tasks",
        description=(
            "At configured daily, weekly, monthly, and quarterly reset times, "
            "uncheck completed tasks in each matching task view and record "
            "tasks that were still active as missed."
        ),
        action_type="reset_view_tasks",
        scope=ScopeConfig(
            fixed={"kind": "all"},
            allowed_kinds=("all",),
        ),
        activations=("schedule",),
        bindings=(),
        companion=None,
        ai=None,
        default_schedule="daily 23:59",
        default_enabled=False,
        fan_out=False,
    ),
}


LEGACY_AUTOMATION_ALIASES: dict[str, str] = {
    "weekly_process_refresh": "process_refresh",
}

VIEW_TASK_RESET_DEFAULTS: dict[str, dict[str, Any]] = {
    "daily": {
        "enabled": True,
        "schedule": "daily 23:59",
    },
    "weekly": {
        "enabled": True,
        "schedule": "weekly sat 23:59",
    },
    "monthly": {
        "enabled": True,
        "schedule": "monthly last sat 23:59",
    },
    "quarterly": {
        "enabled": True,
        "schedule": "quarterly 3 last sat 23:59",
        "interval_months": 3,
        "sync_with_monthly": True,
    },
}


def _normalize_automation_identity(
    key: str | None = None,
    action_type: str | None = None,
) -> tuple[str | None, str | None]:
    if key and key in LEGACY_AUTOMATION_ALIASES:
        key = LEGACY_AUTOMATION_ALIASES[key]
    if action_type and action_type in LEGACY_AUTOMATION_ALIASES:
        action_type = LEGACY_AUTOMATION_ALIASES[action_type]
    return key, action_type


def get_definition(key: str | None = None, action_type: str | None = None) -> AutomationDefinition | None:
    key, action_type = _normalize_automation_identity(key, action_type)
    if key and key in AUTOMATION_DEFINITIONS:
        return AUTOMATION_DEFINITIONS[key]
    if action_type:
        for definition in AUTOMATION_DEFINITIONS.values():
            if definition.action_type == action_type:
                return definition
    return None


def list_definitions() -> list[AutomationDefinition]:
    return list(AUTOMATION_DEFINITIONS.values())


def allowed_trigger_types(key: str | None, action_type: str | None = None) -> tuple[str, ...]:
    definition = get_definition(key, action_type)
    if definition is None:
        return ("schedule", "event", "task", "manual")
    activations = list(definition.activations)
    if "manual" not in activations:
        activations.append("manual")
    return tuple(activations)


def bindings_dict(definition: AutomationDefinition) -> dict[str, Any]:
    return {
        "files": [
            {"role": binding.role, "match": dict(binding.match)}
            for binding in definition.bindings
        ],
    }


def companion_params(definition: AutomationDefinition) -> dict[str, Any] | None:
    if definition.companion is None:
        return None
    companion = definition.companion
    return {
        "enabled": companion.enabled,
        "view_type": companion.default_view_type,
        "section_name": companion.default_section_name,
        "flow_key": companion.flow_key,
        "title_template": companion.title_template,
    }


def default_params(key: str) -> dict[str, Any]:
    definition = get_definition(key)
    if definition is None:
        return generic_default_params()
    result: dict[str, Any] = {
        "version": PARAMS_VERSION,
        "scope": dict(definition.scope.fixed),
        "bindings": bindings_dict(definition),
        "companion_task": companion_params(definition),
    }
    if definition.key == "process_recap_update":
        result["event"] = "file_changed"
        result["recap"] = {"max_date_groups": 5}
    if definition.key == "view_task_reset":
        result["target_view"] = "weekly"
        result["view_resets"] = {
            view_type: dict(config)
            for view_type, config in VIEW_TASK_RESET_DEFAULTS.items()
        }
        result["report"] = {
            "topic_name": "Automations",
            "file_type": "doc",
            "archive": True,
        }
    if "event" in definition.activations:
        trigger = definition.change_trigger or ChangeTriggerConfig()
        result["change_trigger"] = _change_trigger_to_dict(trigger)
    return result


def generic_default_params() -> dict[str, Any]:
    return {
        "version": PARAMS_VERSION,
        "scope": {"kind": "all"},
        "bindings": {"files": []},
        "companion_task": None,
    }


def _scope_needs_default(scope: Any) -> bool:
    if not scope or not isinstance(scope, dict):
        return True
    kind = scope.get("kind")
    if not kind:
        return True
    if kind == "topic_type" and not scope.get("topic_type"):
        return True
    if kind == "topic" and scope.get("topic_id") is None and not scope.get("topic_name"):
        return True
    return False


def _bindings_need_default(bindings: Any, definition: AutomationDefinition) -> bool:
    if not bindings or not isinstance(bindings, dict):
        return True
    files = bindings.get("files")
    if not files:
        return True
    required_roles = set(binding_roles(definition))
    if not required_roles:
        return False
    stored_roles = {binding.get("role") for binding in files if binding.get("role")}
    return not required_roles.issubset(stored_roles)


def apply_definition_to_params(
    params: dict[str, Any] | None,
    key: str | None,
    action_type: str | None = None,
) -> dict[str, Any]:
    """Hydrate params from definition defaults; keep instance overrides where complete."""
    definition = get_definition(key, action_type)
    raw = dict(params or {})
    if definition is None:
        merged = generic_default_params()
        merged.update(raw)
        merged["version"] = PARAMS_VERSION
        merged["scope"] = dict(raw.get("scope") or merged["scope"])
        merged["bindings"] = dict(raw.get("bindings") or merged["bindings"])
        if raw.get("companion_task") is not None:
            merged["companion_task"] = dict(raw["companion_task"])
        if raw.get("trigger"):
            merged["trigger"] = dict(raw["trigger"])
        return merged

    defaults = default_params(definition.key)
    merged = dict(defaults)
    merged["version"] = PARAMS_VERSION

    if not _scope_needs_default(raw.get("scope")):
        merged["scope"] = dict(raw["scope"])
    if not _bindings_need_default(raw.get("bindings"), definition):
        merged["bindings"] = {
            "files": [
                {"role": binding.get("role"), "match": dict(binding.get("match") or {})}
                for binding in (raw.get("bindings") or {}).get("files") or []
            ],
        }

    if defaults.get("companion_task") is not None:
        companion = dict(defaults["companion_task"])
        companion.update(dict(raw.get("companion_task") or {}))
        merged["companion_task"] = companion
    elif raw.get("companion_task") is not None:
        merged["companion_task"] = dict(raw["companion_task"])
    else:
        merged["companion_task"] = None

    if raw.get("trigger"):
        merged["trigger"] = dict(raw["trigger"])

    if raw.get("recap"):
        recap = dict(merged.get("recap") or {})
        recap.update(dict(raw["recap"]))
        merged["recap"] = recap

    if raw.get("change_trigger"):
        change_trigger = dict(merged.get("change_trigger") or {})
        change_trigger.update(dict(raw["change_trigger"]))
        merged["change_trigger"] = change_trigger

    if raw.get("target_view"):
        merged["target_view"] = raw["target_view"]

    if raw.get("view_resets"):
        resets = {
            view_type: dict(config)
            for view_type, config in (merged.get("view_resets") or {}).items()
        }
        for view_type, config in dict(raw["view_resets"]).items():
            if view_type not in VIEW_TASK_RESET_DEFAULTS or not isinstance(config, dict):
                continue
            reset_config = dict(resets.get(view_type) or {})
            reset_config.update(dict(config))
            if view_type == "quarterly":
                interval = reset_config.get("interval_months")
                if interval not in (3, 4):
                    interval = 3
                reset_config["interval_months"] = interval
            resets[view_type] = reset_config
        merged["view_resets"] = resets

    if raw.get("report"):
        report = dict(merged.get("report") or {})
        report.update(dict(raw["report"]))
        merged["report"] = report

    for legacy_key in ("topic_name", "name", "type", "event"):
        if legacy_key in raw:
            merged[legacy_key] = raw[legacy_key]

    return merged


def binding_roles(definition: AutomationDefinition) -> list[str]:
    return [binding.role for binding in definition.bindings]


def resolve_files_by_bindings(topic_id: int, params: dict[str, Any]) -> dict[str, Any]:
    """Resolve topic files by binding roles defined in params.bindings."""
    from models import File

    bindings = (params.get("bindings") or {}).get("files") or []
    if not bindings:
        return {}

    file_types = []
    for binding in bindings:
        match = binding.get("match") or {}
        file_type = match.get("type")
        if file_type and file_type not in file_types:
            file_types.append(file_type)

    if not file_types:
        return {}

    files = (
        File.query.filter_by(topic_id=topic_id)
        .filter(File.type.in_(file_types))
        .filter(File.archived_at.is_(None))
        .order_by(File.order_index, File.id)
        .all()
    )
    by_type: dict[str, Any] = {}
    for file in files:
        by_type.setdefault(file.type, file)

    resolved: dict[str, Any] = {}
    for binding in bindings:
        role = binding.get("role")
        match = binding.get("match") or {}
        file_type = match.get("type")
        if not role or not file_type:
            continue
        candidate = by_type.get(file_type)
        if candidate is None:
            continue
        expected_name = match.get("name")
        if expected_name and candidate.name != expected_name:
            continue
        resolved[role] = candidate
    return resolved


def topic_in_scope(topic, scope: dict[str, Any]) -> bool:
    if topic is None:
        return False
    kind = scope.get("kind", "all")
    if kind == "all":
        return True
    if kind == "topic_type":
        return topic.type == scope.get("topic_type")
    if kind == "topic":
        if scope.get("topic_id") is not None:
            return topic.id == int(scope["topic_id"])
        topic_name = scope.get("topic_name")
        if topic_name:
            return topic.name == topic_name
    return False


def validate_rule_update(
    rule,
    data: dict[str, Any],
) -> str | None:
    """Return error message if invalid, else None. Identity fields only on save."""
    definition = get_definition(rule.key, rule.action_type)
    if definition is None:
        return None

    if "action_type" in data and data["action_type"] != definition.action_type:
        return f"action_type cannot be changed for {rule.key}"

    if "key" in data and data["key"] != definition.key:
        return f"key cannot be changed for built-in automation {rule.key}"

    return None


def validate_rule_activation(rule, trigger_source: str | None = None) -> str | None:
    """Validate stored rule config when enqueueing or executing a run."""
    definition = get_definition(rule.key, rule.action_type)
    if definition is None:
        return None

    from services.automation_params import normalize_params

    params = normalize_params(rule.params, rule.key, rule.action_type)
    scope = params.get("scope") or {}
    scope_kind = scope.get("kind", "all")
    if scope_kind not in definition.scope.allowed_kinds:
        return f"{rule.key} does not support scope kind '{scope_kind}'"

    if trigger_source == "manual":
        allowed = set(allowed_trigger_types(rule.key, rule.action_type))
        if "manual" not in allowed:
            return f"{rule.key} does not support manual activation"
    elif trigger_source:
        if trigger_source not in definition.activations:
            return (
                f"{rule.key} does not support activation via '{trigger_source}'"
            )
    elif rule.trigger_type not in definition.activations:
        return (
            f"{rule.key} does not support activation via '{rule.trigger_type}'"
        )

    stored_bindings = (params.get("bindings") or {}).get("files") or []
    stored_roles = {binding.get("role") for binding in stored_bindings if binding.get("role")}
    required_roles = set(binding_roles(definition))
    if required_roles and not required_roles.issubset(stored_roles):
        missing = ", ".join(sorted(required_roles - stored_roles))
        return f"{rule.key} is missing binding roles: {missing}"

    return None


def default_create_payload(key: str) -> dict[str, Any] | None:
    definition = get_definition(key)
    if definition is None:
        return None
    return {
        "key": definition.key,
        "name": definition.name,
        "action_type": definition.action_type,
        "trigger_type": definition.activations[0],
        "schedule": definition.default_schedule,
        "timezone": definition.timezone_default,
        "enabled": definition.default_enabled,
        "params": default_params(key),
    }
