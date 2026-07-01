from models import AutomationRule
from services.automation_params import normalize_params, trigger_config


def trigger_task_ids():
    ids = set()
    for rule in AutomationRule.query.filter_by(trigger_type="task").all():
        params = normalize_params(rule.params, rule.key, rule.action_type)
        trigger = trigger_config(params) or {}
        task_id = trigger.get("task_id")
        if task_id is not None:
            ids.add(int(task_id))
    return ids


def rules_for_trigger_task(task_id, enabled_only=True):
    if task_id is None:
        return []
    matches = []
    query = AutomationRule.query.filter_by(trigger_type="task")
    if enabled_only:
        query = query.filter_by(enabled=True)
    for rule in query.all():
        params = normalize_params(rule.params, rule.key, rule.action_type)
        trigger = trigger_config(params) or {}
        if int(trigger.get("task_id") or 0) == int(task_id):
            matches.append(rule)
    return matches


def rule_keys_for_trigger_task(task_id, enabled_only=True):
    return [rule.key for rule in rules_for_trigger_task(task_id, enabled_only=enabled_only)]
