"""Section-window automations and complimentary input/review tasks.

A view section can own one `section_window` automation (start + duration).
Regular automations that need user input or review lock their clock to that
window and place two complimentary tasks in a routine section.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta

from models import (
    AgentPendingReview,
    AiAction,
    Automation,
    AutomationRun,
    Task,
    Topic,
    View,
    ViewTaskMembership,
    db,
)
from areas.automations.services.automation_schedule import as_utc_naive
from areas.automations.services.scope import resolve_scope
from areas.objects.services.task_ops import ACTIVE, DONE, set_task_status

KIND_STANDARD = "standard"
KIND_SECTION_WINDOW = "section_window"
CADENCE_ROUTINE = "routine"
CADENCE_ONE_TIME = "one_time"
ROLE_INPUT = "input"
ROLE_REVIEW = "review"


def new_section_key() -> str:
    return uuid.uuid4().hex


def section_defs(layout: dict | None) -> list[dict]:
    raw = (layout or {}).get("sections")
    if not isinstance(raw, list):
        return []
    out = []
    for item in raw:
        if not isinstance(item, dict):
            continue
        name = str(item.get("name") or "").strip()
        if not name:
            continue
        out.append(item)
    return out


def ensure_section_keys(layout: dict | None) -> tuple[dict, bool]:
    """Give every named section a stable key. Returns (layout, changed)."""
    config = dict(layout or {})
    sections = section_defs(config)
    changed = False
    next_sections = []
    for item in sections:
        row = dict(item)
        if not str(row.get("key") or "").strip():
            row["key"] = new_section_key()
            changed = True
        cadence = str(row.get("cadence") or "").strip()
        if cadence not in (CADENCE_ROUTINE, CADENCE_ONE_TIME):
            row["cadence"] = CADENCE_ROUTINE
            changed = True
        next_sections.append(row)
    if changed:
        config["sections"] = next_sections
    return config, changed


def find_section(layout: dict | None, *, key: str | None = None, name: str | None = None):
    for item in section_defs(layout):
        if key and str(item.get("key") or "") == key:
            return item
        if name and str(item.get("name") or "").strip() == name:
            return item
    return None


def section_cadence(layout: dict | None, section_key: str | None) -> str:
    found = find_section(layout, key=section_key)
    cadence = str((found or {}).get("cadence") or CADENCE_ROUTINE)
    return cadence if cadence in (CADENCE_ROUTINE, CADENCE_ONE_TIME) else CADENCE_ROUTINE


def section_name_for_key(layout: dict | None, section_key: str | None) -> str:
    found = find_section(layout, key=section_key)
    return str((found or {}).get("name") or "").strip()


def window_is_open(automation: Automation, now: datetime | None = None) -> bool:
    if (automation.kind or KIND_STANDARD) != KIND_SECTION_WINDOW:
        return False
    if automation.window_opened_at is None:
        return False
    if automation.pending_clear:
        return False
    now = as_utc_naive(now or datetime.utcnow())
    closes = as_utc_naive(automation.window_closes_at)
    if now is not None and closes is not None and now >= closes:
        return False
    return True


def _memberships_in_section(view_id: int, section_name: str) -> list[ViewTaskMembership]:
    return (
        ViewTaskMembership.query.filter_by(view_id=view_id, section_name=section_name)
        .all()
    )


def tasks_in_section(view_id: int, section_name: str) -> list[Task]:
    rows = _memberships_in_section(view_id, section_name)
    tasks = []
    for row in rows:
        if row.task_id is None:
            continue
        task = db.session.get(Task, row.task_id)
        if task is None or task.archived_at is not None:
            continue
        tasks.append(task)
    return tasks


def leftover_active_tasks(view_id: int, section_name: str) -> list[Task]:
    return [t for t in tasks_in_section(view_id, section_name) if t.status != DONE]


def section_has_active_tasks(view_id: int, section_name: str) -> bool:
    return bool(leftover_active_tasks(view_id, section_name))


def attention_for_window(automation: Automation, now: datetime | None = None) -> bool:
    if not window_is_open(automation, now):
        return False
    view = db.session.get(View, automation.view_id) if automation.view_id else None
    if view is None:
        return False
    name = section_name_for_key(view.layout_config, automation.section_key)
    if not name:
        return False
    return section_has_active_tasks(view.id, name)


def enrich_automation(automation: Automation, now: datetime | None = None) -> dict:
    data = automation.to_dict()
    now = now or datetime.utcnow()
    data["window_open"] = window_is_open(automation, now)
    data["attention"] = attention_for_window(automation, now)
    return data


def _window_for(view_id: int, section_key: str) -> Automation | None:
    return Automation.query.filter_by(
        kind=KIND_SECTION_WINDOW,
        view_id=view_id,
        section_key=section_key,
    ).first()


def linked_standard_automations(view_id: int, section_key: str) -> list[Automation]:
    return (
        Automation.query.filter_by(
            kind=KIND_STANDARD,
            view_id=view_id,
            section_key=section_key,
        )
        .order_by(Automation.id)
        .all()
    )


def _step_requires_user_input(step: dict) -> bool:
    if step.get("kind") != "ai":
        return False
    if step.get("requires_user_input"):
        return True
    action_id = step.get("action_id")
    if action_id is None:
        return False
    action = db.session.get(AiAction, int(action_id))
    return bool(action and action.requires_user_input)


def _step_needs_review(step: dict) -> bool:
    if step.get("kind") != "ai":
        return False
    mode = step.get("apply_mode")
    if mode == "review":
        return True
    if mode or step.get("action_id") is None:
        return False
    action = db.session.get(AiAction, int(step["action_id"]))
    return bool(action and action.apply_mode == "review")


def automation_requires_user_input(automation: Automation) -> bool:
    return any(_step_requires_user_input(step) for step in (automation.steps or []))


def automation_needs_review(automation: Automation) -> bool:
    return any(_step_needs_review(step) for step in (automation.steps or []))


def needs_complimentary_placement(automation: Automation) -> bool:
    return automation_requires_user_input(automation) or automation_needs_review(
        automation
    )


def complimentary_titles(automation: Automation) -> dict[str, str]:
    name = (automation.name or "").strip() or "Automation"
    name_he = (automation.name_he or "").strip() or name
    return {
        ROLE_INPUT: f"{name} automation task",
        ROLE_REVIEW: f"{name} review task",
        f"{ROLE_INPUT}_he": f"{name_he} משימת אוטומציה",
        f"{ROLE_REVIEW}_he": f"{name_he} משימת סקירה",
    }


def complimentary_tasks_for(automation_id: int) -> list[Task]:
    return (
        Task.query.filter_by(source_automation_id=automation_id)
        .filter(Task.archived_at.is_(None))
        .order_by(Task.id)
        .all()
    )


def complimentary_task(automation_id: int, role: str) -> Task | None:
    return (
        Task.query.filter_by(
            source_automation_id=automation_id,
            complimentary_role=role,
        )
        .filter(Task.archived_at.is_(None))
        .first()
    )


def _place_task_in_section(task: Task, view: View, section: dict) -> None:
    name = str(section.get("name") or "").strip()
    flag = section.get("flag")
    existing = ViewTaskMembership.query.filter_by(
        view_id=view.id, task_id=task.id
    ).first()
    if existing:
        existing.section_name = name
        existing.section_flag = flag
        return
    count = ViewTaskMembership.query.filter_by(view_id=view.id).count()
    db.session.add(
        ViewTaskMembership(
            view_id=view.id,
            task_id=task.id,
            section_name=name,
            section_flag=flag,
            order_index=count,
            topic_order_index=count,
        )
    )


def ensure_complimentary_tasks(automation: Automation) -> list[Task]:
    if (automation.kind or KIND_STANDARD) != KIND_STANDARD:
        return []
    if not needs_complimentary_placement(automation):
        return complimentary_tasks_for(automation.id)
    if not automation.view_id or not automation.section_key:
        raise ValueError("this automation needs a routine view section")
    view = db.session.get(View, automation.view_id)
    if view is None:
        raise ValueError("view not found")
    section = find_section(view.layout_config, key=automation.section_key)
    if section is None:
        raise ValueError("section not found")
    if section_cadence(view.layout_config, automation.section_key) != CADENCE_ROUTINE:
        raise ValueError("complimentary tasks must sit in a routine section")

    titles = complimentary_titles(automation)
    created = []
    for role in (ROLE_INPUT, ROLE_REVIEW):
        task = complimentary_task(automation.id, role)
        if task is None:
            task = Task(
                title=titles[role],
                status=ACTIVE,
                list_order_index=0,
                source_automation_id=automation.id,
                complimentary_role=role,
                complimentary_cycle={},
            )
            db.session.add(task)
            db.session.flush()
        else:
            task.title = titles[role]
        _place_task_in_section(task, view, section)
        created.append(task)
    db.session.flush()
    return created


def delete_complimentary_tasks(automation_id: int) -> None:
    for task in Task.query.filter_by(source_automation_id=automation_id).all():
        from areas.objects.services.delete_cascade import delete_task_cascade

        delete_task_cascade(task.id)


def recycle_complimentary(automation: Automation) -> None:
    for task in complimentary_tasks_for(automation.id):
        if task.status == DONE:
            set_task_status(task, done=False)
        task.complimentary_cycle = {}
    automation.pending_user_input = None


def _recycle_routine_section(view: View, section_key: str) -> None:
    if section_cadence(view.layout_config, section_key) != CADENCE_ROUTINE:
        return
    name = section_name_for_key(view.layout_config, section_key)
    if not name:
        return
    for task in tasks_in_section(view.id, name):
        if task.complimentary_role:
            continue
        if task.status == DONE:
            set_task_status(task, done=False)


def sync_linked_schedules(window: Automation) -> None:
    if not window.view_id or not window.section_key:
        return
    for automation in linked_standard_automations(window.view_id, window.section_key):
        automation.schedule = window.schedule
        automation.timezone = window.timezone
        automation.next_run_at = None


def _mark_complimentary(automation: Automation, role: str, *, done: bool) -> None:
    task = complimentary_task(automation.id, role)
    if task is None:
        return
    set_task_status(task, done=done)


def _fire_linked_at_start(window: Automation) -> None:
    from areas.automations.services.run_automation import run_automation

    if not window.view_id or not window.section_key:
        return
    for automation in linked_standard_automations(window.view_id, window.section_key):
        if not automation.enabled:
            continue
        if automation_requires_user_input(automation):
            continue
        run_automation(automation, trigger_source="section_start")
        _mark_complimentary(automation, ROLE_INPUT, done=True)
        if not automation_needs_review(automation):
            _mark_complimentary(automation, ROLE_REVIEW, done=True)


def open_window(automation: Automation, now: datetime) -> None:
    minutes = int(automation.window_duration_minutes or 0)
    automation.window_opened_at = now
    automation.window_closes_at = now + timedelta(minutes=max(minutes, 1))
    automation.pending_clear = None
    view = db.session.get(View, automation.view_id) if automation.view_id else None
    if view is not None and automation.section_key:
        name = section_name_for_key(view.layout_config, automation.section_key)
        for linked in linked_standard_automations(view.id, automation.section_key):
            recycle_complimentary(linked)
        if name:
            _recycle_routine_section(view, automation.section_key)
    _fire_linked_at_start(automation)


def close_window_or_pending(automation: Automation, now: datetime) -> None:
    view = db.session.get(View, automation.view_id) if automation.view_id else None
    name = (
        section_name_for_key(view.layout_config, automation.section_key)
        if view is not None
        else ""
    )
    leftovers = leftover_active_tasks(view.id, name) if view is not None and name else []
    if leftovers:
        cadence = section_cadence(view.layout_config, automation.section_key) if view else CADENCE_ROUTINE
        automation.pending_clear = {
            "view_id": view.id if view else automation.view_id,
            "view_name": view.name if view else "",
            "section_key": automation.section_key,
            "section_name": name,
            "cadence": cadence,
            "leftovers": [
                {
                    "id": task.id,
                    "title": task.title,
                    "cadence": cadence,
                    "complimentary_role": task.complimentary_role,
                }
                for task in leftovers
            ],
        }
        return
    automation.window_opened_at = None
    automation.window_closes_at = None
    automation.pending_clear = None


def apply_leftover_clear(automation: Automation) -> dict:
    payload = automation.pending_clear or {}
    leftovers = payload.get("leftovers") or []
    cadence = payload.get("cadence") or CADENCE_ROUTINE
    view = db.session.get(View, automation.view_id) if automation.view_id else None
    archived = 0
    unmarked = 0
    now = datetime.utcnow()
    leftover_ids = {int(item["id"]) for item in leftovers if item.get("id") is not None}

    for item in leftovers:
        task_id = item.get("id")
        if task_id is None:
            continue
        task = db.session.get(Task, int(task_id))
        if task is None or task.archived_at is not None:
            continue
        item_cadence = item.get("cadence") or cadence
        if item_cadence == CADENCE_ONE_TIME:
            task.archived_at = now
            archived += 1

    if view is not None and cadence == CADENCE_ROUTINE:
        name = payload.get("section_name") or section_name_for_key(
            view.layout_config, automation.section_key
        )
        if name:
            for task in tasks_in_section(view.id, name):
                if task.id in leftover_ids and cadence == CADENCE_ONE_TIME:
                    continue
                if task.status == DONE:
                    set_task_status(task, done=False)
                    unmarked += 1

    automation.pending_clear = None
    automation.window_opened_at = None
    automation.window_closes_at = None
    db.session.flush()
    return {"archived": archived, "unmarked": unmarked}


def pending_clears(workspace_id: int) -> list[dict]:
    rows = (
        Automation.query.filter_by(
            workspace_id=workspace_id, kind=KIND_SECTION_WINDOW
        )
        .filter(Automation.pending_clear.isnot(None))
        .order_by(Automation.id)
        .all()
    )
    return [enrich_automation(row) for row in rows if row.pending_clear]


def input_topics(automation: Automation) -> list[dict]:
    resolved = resolve_scope(automation.scope, workspace_id=automation.workspace_id)
    ids = resolved.get("topic_ids") or []
    if not ids:
        rows = (
            Topic.query.filter_by(workspace_id=automation.workspace_id)
            .filter(Topic.archived_at.is_(None))
            .order_by(Topic.order_index, Topic.id)
            .all()
        )
        return [{"id": t.id, "name": t.name} for t in rows]
    topics = (
        Topic.query.filter(Topic.id.in_([int(i) for i in ids]))
        .order_by(Topic.order_index, Topic.id)
        .all()
    )
    return [{"id": t.id, "name": t.name} for t in topics]


def store_user_input(automation: Automation, payload: dict) -> dict:
    text = str(payload.get("text") or "").strip()
    by_topic = payload.get("by_topic") or {}
    cleaned = {}
    if isinstance(by_topic, dict):
        for key, value in by_topic.items():
            cleaned[str(key)] = str(value or "").strip()
    stored = {
        "text": text,
        "by_topic": cleaned,
        "submitted_at": datetime.utcnow().isoformat(),
    }
    automation.pending_user_input = stored
    task = complimentary_task(automation.id, ROLE_INPUT)
    if task is not None:
        cycle = dict(task.complimentary_cycle or {})
        cycle["input_received"] = True
        task.complimentary_cycle = cycle
    db.session.flush()
    return stored


def format_user_input_for_prompt(payload: dict | None) -> str:
    if not payload:
        return ""
    by_topic = payload.get("by_topic") or {}
    lines = []
    if isinstance(by_topic, dict):
        for key, value in by_topic.items():
            if not str(value or "").strip():
                continue
            topic = db.session.get(Topic, int(key)) if str(key).isdigit() else None
            label = topic.name if topic is not None else key
            lines.append(f"- {label}: {value}")
    text = str(payload.get("text") or "").strip()
    if text and not lines:
        return text
    if text:
        lines.insert(0, text)
    return "\n".join(lines)


def review_status(automation: Automation) -> dict:
    latest = (
        AutomationRun.query.filter_by(automation_id=automation.id)
        .order_by(AutomationRun.id.desc())
        .first()
    )
    file_ids = []
    if latest and isinstance(latest.result, dict):
        for step in latest.result.get("steps") or []:
            if not isinstance(step, dict):
                continue
            ids = step.get("pending_review_ids") or []
            file_ids.extend(int(i) for i in ids if i is not None)
            agent = step.get("agent") or {}
            if isinstance(agent, dict):
                more = agent.get("pending_review_ids") or []
                file_ids.extend(int(i) for i in more if i is not None)
    file_ids = list(dict.fromkeys(file_ids))
    pending = []
    if file_ids:
        rows = AgentPendingReview.query.filter(
            AgentPendingReview.file_id.in_(file_ids)
        ).all()
        pending = [row.file_id for row in rows]
    input_task = complimentary_task(automation.id, ROLE_INPUT)
    review_task = complimentary_task(automation.id, ROLE_REVIEW)
    received = False
    if input_task is not None:
        received = bool((input_task.complimentary_cycle or {}).get("input_received"))
    if automation.pending_user_input:
        received = True
    return {
        "has_pending_review": bool(pending),
        "file_ids": pending,
        "input_received": received,
        "input_task_id": input_task.id if input_task else None,
        "review_task_id": review_task.id if review_task else None,
        "input_done": bool(input_task and input_task.status == DONE),
        "review_done": bool(review_task and review_task.status == DONE),
    }


def complete_review_if_clear(automation: Automation) -> bool:
    status = review_status(automation)
    if status["has_pending_review"]:
        return False
    _mark_complimentary(automation, ROLE_REVIEW, done=True)
    return True


def mark_input_done(automation: Automation) -> None:
    _mark_complimentary(automation, ROLE_INPUT, done=True)


def ensure_section_windows(workspace_id: int) -> list[Automation]:
    views = View.query.filter_by(workspace_id=workspace_id).filter(
        View.archived_at.is_(None)
    ).all()
    kept_keys: set[tuple[int, str]] = set()
    created = []
    for view in views:
        layout, changed = ensure_section_keys(view.layout_config)
        if changed:
            view.layout_config = layout
            db.session.add(view)
        for section in section_defs(layout):
            key = str(section.get("key") or "")
            if not key:
                continue
            kept_keys.add((view.id, key))
            existing = _window_for(view.id, key)
            name = str(section.get("name") or "").strip()
            label = f"{view.name} / {name}"
            if existing is None:
                row = Automation(
                    workspace_id=workspace_id,
                    name=label,
                    name_he=label,
                    kind=KIND_SECTION_WINDOW,
                    view_id=view.id,
                    section_key=key,
                    trigger={"type": "schedule"},
                    scope={"kind": "all"},
                    steps=[],
                    enabled=False,
                    timezone="Asia/Jerusalem",
                )
                db.session.add(row)
                created.append(row)
            else:
                existing.name = label
                existing.name_he = label
    orphans = (
        Automation.query.filter_by(
            workspace_id=workspace_id, kind=KIND_SECTION_WINDOW
        )
        .all()
    )
    for row in orphans:
        if row.view_id and row.section_key and (row.view_id, row.section_key) in kept_keys:
            continue
        from areas.objects.services.delete_cascade import delete_automation_cascade

        delete_automation_cascade(row.id)
    db.session.flush()
    return created


def tick_section_window(automation: Automation, *, now: datetime, action: str, planned) -> None:
    """Advance one section window. `action` is plan_tick's start decision."""
    now = as_utc_naive(now) or now
    if window_is_open(automation, now) and automation.window_closes_at:
        closes = as_utc_naive(automation.window_closes_at) or automation.window_closes_at
        if now >= closes:
            close_window_or_pending(automation, now)
    if action == "run" and not window_is_open(automation, now) and not automation.pending_clear:
        open_window(automation, now)
    if planned is not None:
        automation.next_run_at = planned
