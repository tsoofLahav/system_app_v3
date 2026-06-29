from models import AutomationRule
from services.automation_runner import enqueue_run


def dispatch_file_changed(file_id, change, meta=None):
    if file_id is None:
        return []

    rules = AutomationRule.query.filter_by(enabled=True, trigger_type="event").all()
    run_ids = []
    for rule in rules:
        params = rule.params or {}
        if params.get("event") != "file_changed":
            continue
        rule_file_id = params.get("file_id")
        if rule_file_id is None:
            continue
        if int(rule_file_id) != int(file_id):
            continue

        event_context = {
            "event": "file_changed",
            "file_id": file_id,
            "change": change,
        }
        if meta:
            event_context.update(meta)

        run = enqueue_run(rule, trigger_source="event", event_context=event_context)
        if run is not None:
            run_ids.append(run["id"])
    return run_ids
