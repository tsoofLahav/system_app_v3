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
            "default_params": default_params(self.key),
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
    "weekly_process_refresh": AutomationDefinition(
        key="weekly_process_refresh",
        name="Update all processes",
        description=(
            "For each process topic, run a smart update on plan, doc, and tasks files."
        ),
        action_type="weekly_process_refresh",
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
}


def get_definition(key: str | None, action_type: str | None = None) -> AutomationDefinition | None:
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
        return {
            "version": PARAMS_VERSION,
            "scope": {"kind": "all"},
            "bindings": {"files": []},
            "companion_task": None,
        }
    result: dict[str, Any] = {
        "version": PARAMS_VERSION,
        "scope": dict(definition.scope.fixed),
        "bindings": bindings_dict(definition),
        "companion_task": companion_params(definition),
    }
    return result


def apply_definition_to_params(
    params: dict[str, Any] | None,
    key: str | None,
    action_type: str | None = None,
) -> dict[str, Any]:
    """Merge instance params with definition defaults; scope/bindings always from definition in v1."""
    definition = get_definition(key, action_type)
    raw = dict(params or {})
    if definition is None:
        if raw.get("version") != PARAMS_VERSION:
            raw["version"] = PARAMS_VERSION
        return raw

    merged = dict(raw)
    merged["version"] = PARAMS_VERSION
    merged["scope"] = dict(definition.scope.fixed)
    merged["bindings"] = bindings_dict(definition)

    companion_default = companion_params(definition)
    if companion_default is not None:
        instance_companion = dict(merged.get("companion_task") or {})
        for field_name in ("view_type", "section_name"):
            if field_name in instance_companion:
                companion_default[field_name] = instance_companion[field_name]
        merged["companion_task"] = companion_default
    else:
        merged["companion_task"] = None

    if "trigger" in raw:
        merged["trigger"] = dict(raw["trigger"])

    for legacy_key in ("topic_name", "name", "type"):
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
    """Return error message if invalid, else None."""
    definition = get_definition(rule.key, rule.action_type)
    if definition is None:
        return None

    trigger_type = data.get("trigger_type", rule.trigger_type)
    allowed = set(allowed_trigger_types(rule.key, rule.action_type))
    if trigger_type not in allowed:
        return f"trigger_type '{trigger_type}' is not allowed for {rule.key}"

    if "action_type" in data and data["action_type"] != definition.action_type:
        return f"action_type cannot be changed for {rule.key}"

    if "key" in data and data["key"] != definition.key:
        return f"key cannot be changed for built-in automation {rule.key}"

    params = data.get("params")
    if isinstance(params, dict):
        if "scope" in params:
            return "params.scope is fixed for built-in automations"
        if "bindings" in params:
            return "params.bindings is fixed for built-in automations"

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
