from services.automation_schedule import next_run_after

VIEW_RESET_VIEW_TYPES = ("daily", "weekly", "monthly", "quarterly")


def view_reset_configs(params):
    resets = params.get("view_resets")
    if isinstance(resets, dict) and resets:
        return {
            view_type: dict(resets.get(view_type) or {})
            for view_type in VIEW_RESET_VIEW_TYPES
        }

    target_view = (params.get("target_view") or "weekly").strip()
    return {
        target_view: {
            "enabled": True,
            "schedule": params.get("schedule") or _default_schedule_for_view(target_view),
        }
    }


def due_view_resets(params, baseline_utc, now_utc, timezone):
    due = []
    for view_type, config in view_reset_configs(params).items():
        if not config.get("enabled", True):
            continue
        schedule = config.get("schedule") or _default_schedule_for_view(view_type)
        if next_run_after(schedule, baseline_utc, timezone=timezone) <= now_utc:
            due.append({"view_type": view_type, "schedule": schedule})
    return due


def next_view_reset_run(params, after_utc, timezone):
    candidates = []
    for view_type, config in view_reset_configs(params).items():
        if not config.get("enabled", True):
            continue
        schedule = config.get("schedule") or _default_schedule_for_view(view_type)
        candidates.append(next_run_after(schedule, after_utc, timezone=timezone))
    return min(candidates) if candidates else None


def _default_schedule_for_view(view_type):
    return {
        "daily": "daily 23:59",
        "weekly": "weekly sat 23:59",
        "monthly": "monthly last sat 23:59",
        "quarterly": "quarterly 3 last sat 23:59",
    }.get(view_type, "weekly sat 23:59")
