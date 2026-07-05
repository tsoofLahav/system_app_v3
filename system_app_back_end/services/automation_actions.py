from datetime import datetime

from sqlalchemy import or_

from models import Block, File, Task, TaskResetAcknowledgement, TaskView, Topic, db
from services.ai_proposal_actions import (
    create_process_refresh_skipped_proposal,
    create_smart_process_update_proposal,
)
from services.ai_recap_actions import smart_process_recap_update
from services.ai_project_summary_actions import smart_project_summary_update
from services.automation_companion import companion_title, create_companion_task
from services.automation_definitions import get_definition, resolve_files_by_bindings, topic_in_scope
from services.automation_params import companion_config, normalize_params
from services.automation_topics import AUTOMATIONS_TOPIC_KEY


DEFAULT_BLOCKS = {
    "text": [("text", {"text": ""})],
    "main": [("text", {"text": ""})],
    "doc": [("text", {"text": ""})],
    "plan": [("text", {"text": ""})],
    "tasks": [("task_list", {})],
    "execution": [
        ("header", {"text": "", "level": 2}),
        ("list", {"items": [{"text": ""}]}),
        ("text", {"text": ""}),
    ],
}


def run_action(rule, run=None):
    context = build_run_context(rule, run)
    action_type = rule.action_type
    if action_type == "create_file_by_time":
        return create_file_by_time(context)
    if action_type == "archive_at_time":
        return archive_at_time(context)
    if action_type == "rotate_daily_main_file":
        return rotate_daily_main_file(context)
    if action_type in {"process_refresh", "weekly_process_refresh"}:
        return process_refresh(context)
    if action_type == "process_recap_update":
        return process_recap_update(context)
    if action_type == "project_summary_update":
        return project_summary_update(context)
    if action_type == "reset_view_tasks":
        return reset_view_tasks(context)
    raise ValueError(f"Unknown automation action: {action_type}")


def build_run_context(rule, run=None):
    params = normalize_params(rule.params, rule.key, rule.action_type)
    event_context = {}
    if run is not None:
        if hasattr(run, "event_context"):
            event_context = run.event_context or {}
        elif isinstance(run, dict):
            event_context = run.get("event_context") or {}

    topic = None
    topic_id = event_context.get("topic_id")
    if topic_id is not None:
        topic = db.session.get(Topic, int(topic_id))
    if topic is None and params.get("scope", {}).get("kind") == "topic":
        topics = _resolve_scope_topics_from_params(params)
        topic = topics[0] if topics else None

    return {
        "rule": rule,
        "run": run,
        "params": params,
        "topic": topic,
        "topic_id": topic.id if topic else None,
        "event_context": event_context,
    }


def create_file_by_time(context):
    params = context["params"]
    topic = _resolve_topic_from_context(context, params)
    file = _create_file(
        topic,
        name=params.get("name", "Text"),
        file_type=params.get("type", "text"),
        is_main=params.get("is_main", True),
    )
    return {"created_file_id": file.id, "topic_id": topic.id}


def archive_at_time(context):
    params = context["params"]
    target_kind = params.get("target_kind", "file")
    target_id = params.get("target_id")
    if not target_id:
        raise ValueError("target_id is required")
    archived_at = datetime.utcnow()
    if target_kind == "topic":
        target = db.session.get(Topic, int(target_id))
    elif target_kind == "file":
        target = db.session.get(File, int(target_id))
    elif target_kind == "block":
        target = db.session.get(Block, int(target_id))
    elif target_kind == "task":
        target = db.session.get(Task, int(target_id))
    else:
        raise ValueError(f"Unsupported archive target: {target_kind}")
    if target is None:
        raise ValueError("archive target not found")
    target.archived_at = archived_at
    db.session.flush()
    return {"archived": {"kind": target_kind, "id": int(target_id)}}


def rotate_daily_main_file(context):
    params = context["params"]
    topic = _resolve_topic_from_context(context, params)
    files_by_role = resolve_files_by_bindings(topic.id, params)
    daily_binding = (params.get("bindings") or {}).get("files") or []
    daily_match = None
    for binding in daily_binding:
        if binding.get("role") == "daily":
            daily_match = binding.get("match") or {}
            break
    daily_name = (
        daily_match.get("name")
        if daily_match
        else params.get("name", "Daily")
    )
    daily_type = (
        daily_match.get("type")
        if daily_match
        else params.get("type", "main")
    )
    existing = files_by_role.get("daily")
    if existing is None:
        existing = (
            File.query.filter_by(topic_id=topic.id, name=daily_name)
            .filter(File.archived_at.is_(None))
            .order_by(File.id.desc())
            .first()
        )
    if existing is not None:
        existing.archived_at = datetime.utcnow()
    file = _create_file(
        topic,
        name=daily_name,
        file_type=daily_type,
        is_main=True,
    )
    return {
        "archived_file_id": existing.id if existing else None,
        "created_file_id": file.id,
        "topic_id": topic.id,
    }


def process_refresh(context):
    rule = context["rule"]
    run = context["run"]
    topic = context["topic"]
    if topic is None:
        raise ValueError("topic is required for process_refresh")
    result = _refresh_process(topic, context["params"])
    _maybe_create_companion_task(rule, run, topic, result)
    return result


def weekly_process_refresh(context):
    """Deprecated alias for process_refresh."""
    return process_refresh(context)


def process_recap_update(context):
    topic = context["topic"]
    if topic is None:
        raise ValueError("topic is required for process_recap_update")

    event_context = context.get("event_context") or {}
    trigger_file_id = event_context.get("file_id")
    if trigger_file_id is not None:
        changed = db.session.get(File, int(trigger_file_id))
        if changed is not None and changed.type == "overview":
            return {
                "topic_id": topic.id,
                "skipped": True,
                "reason": "overview_change",
            }

    params = context["params"]
    files_by_role = resolve_files_by_bindings(topic.id, params)
    missing = [
        role for role in ("overview", "plan", "doc") if role not in files_by_role
    ]
    if missing:
        raise ValueError(
            f"Cannot update recap for process '{topic.name}': "
            f"missing {', '.join(missing)} file(s)."
        )

    recap_params = params.get("recap") or {}
    max_date_groups = int(recap_params.get("max_date_groups") or 5)
    return smart_process_recap_update(
        topic,
        files_by_role["overview"],
        files_by_role["plan"],
        files_by_role["doc"],
        max_date_groups=max_date_groups,
    )


def project_summary_update(context):
    topic = context["topic"]
    if topic is None:
        raise ValueError("topic is required for project_summary_update")

    event_context = context.get("event_context") or {}
    trigger_file_id = event_context.get("file_id")
    if trigger_file_id is not None:
        changed = db.session.get(File, int(trigger_file_id))
        if changed is not None and changed.type == "overview":
            return {
                "topic_id": topic.id,
                "skipped": True,
                "reason": "overview_change",
            }

    params = context["params"]
    files_by_role = resolve_files_by_bindings(topic.id, params)
    missing = [
        role
        for role in ("overview", "plan", "execution", "tasks")
        if role not in files_by_role
    ]
    if missing:
        raise ValueError(
            f"Cannot update project summary for '{topic.name}': "
            f"missing {', '.join(missing)} file(s)."
        )

    summary_params = params.get("project_summary") or {}
    max_date_groups = int(summary_params.get("max_date_groups") or 3)
    return smart_project_summary_update(
        topic,
        files_by_role["overview"],
        files_by_role["plan"],
        files_by_role["execution"],
        files_by_role["tasks"],
        files_by_role.get("doc"),
        max_date_groups=max_date_groups,
    )


def reset_view_tasks(context):
    rule = context["rule"]
    run = context["run"]
    params = context["params"]
    event_context = context.get("event_context") or {}
    view_type = (
        event_context.get("target_view") or params.get("target_view") or "weekly"
    ).strip()
    if not view_type:
        raise ValueError("target_view is required for reset_view_tasks")

    reset_at = datetime.utcnow()
    rows = _task_rows_for_view(view_type)
    reset_tasks = []
    missed_tasks = []

    for task, task_view, topic in rows:
        item = _task_reset_report_item(task, task_view, topic)
        if task.status == "done":
            task.status = "active"
            reset_tasks.append(item)
        else:
            missed_tasks.append(item)

    report_file = _create_task_reset_report_file(
        params,
        view_type,
        reset_at,
        reset_tasks,
        missed_tasks,
    )
    acknowledgement = TaskResetAcknowledgement(
        automation_run_id=run.id if run is not None else None,
        rule_id=rule.id,
        view_type=view_type,
        report_file_id=report_file.id,
        payload={
            "view_type": view_type,
            "reset_at": reset_at.isoformat(),
            "report_file_id": report_file.id,
            "report_topic_id": report_file.topic_id,
            "reset_count": len(reset_tasks),
            "missed_count": len(missed_tasks),
            "reset_tasks": reset_tasks,
            "missed_tasks": missed_tasks,
        },
        status="pending",
    )
    db.session.add(acknowledgement)
    db.session.flush()

    return {
        "view_type": view_type,
        "reset_at": reset_at.isoformat(),
        "reset_count": len(reset_tasks),
        "missed_count": len(missed_tasks),
        "report_file_id": report_file.id,
        "acknowledgement_id": acknowledgement.id,
    }


def _task_rows_for_view(view_type):
    rows = (
        db.session.query(Task, TaskView, Topic)
        .join(TaskView, TaskView.task_id == Task.id)
        .outerjoin(Block, Task.block_id == Block.id)
        .outerjoin(File, Block.file_id == File.id)
        .outerjoin(Topic, File.topic_id == Topic.id)
        .filter(TaskView.view_type == view_type)
        .filter(TaskView.task_id.isnot(None))
        .filter(Task.archived_at.is_(None))
        .filter(or_(TaskView.topic_key.is_(None), TaskView.topic_key != AUTOMATIONS_TOPIC_KEY))
        .filter(
            (Block.id.is_(None))
            | (
                Block.archived_at.is_(None)
                & File.archived_at.is_(None)
                & Topic.archived_at.is_(None)
            )
        )
        .order_by(TaskView.section_name.nulls_last(), Task.id)
        .all()
    )
    return rows


def _task_reset_report_item(task, task_view, topic):
    return {
        "task_id": task.id,
        "title": task.title,
        "previous_status": task.status,
        "section_name": task_view.section_name,
        "topic_id": topic.id if topic is not None else None,
        "topic_name": topic.name if topic is not None else None,
        "due_date": task.due_date.isoformat() if task.due_date else None,
        "created_at": task.created_at.isoformat() if task.created_at else None,
    }


def _create_task_reset_report_file(
    params,
    view_type,
    reset_at,
    reset_tasks,
    missed_tasks,
):
    report_params = params.get("report") or {}
    topic_name = report_params.get("topic_name") or "Automations"
    file_type = report_params.get("file_type") or "doc"
    archive = report_params.get("archive", True)
    topic = _ensure_automations_topic(topic_name)
    file = _create_file(
        topic,
        name=_task_reset_report_name(view_type, reset_at),
        file_type=file_type,
        is_main=False,
        create_defaults=False,
    )
    db.session.add(
        Block(
            file_id=file.id,
            type="text",
            content={
                "text": (
                    f"{view_type.title()} tasks were reset on "
                    f"{reset_at.isoformat()} UTC.\n"
                    f"Unchecked completed tasks: {len(reset_tasks)}.\n"
                    f"Missed tasks still active: {len(missed_tasks)}."
                )
            },
            order_index=0,
        )
    )
    db.session.add(
        Block(
            file_id=file.id,
            type="table",
            content={"rows": _task_reset_report_rows(reset_tasks, missed_tasks)},
            order_index=1,
        )
    )
    if archive:
        file.archived_at = reset_at
    db.session.flush()
    return file


def _ensure_automations_topic(topic_name):
    topic = Topic.query.filter_by(name=topic_name).order_by(Topic.id).first()
    if topic is not None:
        if topic.archived_at is not None:
            topic.archived_at = None
        return topic

    topic = Topic(
        name=topic_name,
        type="area",
        icon="clock",
        color="#37899E",
    )
    db.session.add(topic)
    db.session.flush()
    return topic


def _task_reset_report_name(view_type, reset_at):
    return f"{view_type.title()} missed tasks - {reset_at.date().isoformat()}"


def _task_reset_report_rows(reset_tasks, missed_tasks):
    rows = [["Kind", "Task", "Section", "Topic", "Task ID", "Due date"]]
    for kind, tasks in (("Reset", reset_tasks), ("Missed", missed_tasks)):
        for task in tasks:
            rows.append(
                [
                    kind,
                    task.get("title") or "",
                    task.get("section_name") or "",
                    task.get("topic_name") or "",
                    str(task.get("task_id") or ""),
                    task.get("due_date") or "",
                ]
            )
    if len(rows) == 1:
        rows.append(["No tasks", "", "", "", "", ""])
    return rows


def _refresh_process(topic, params):
    files_by_role = resolve_files_by_bindings(topic.id, params)
    definition = get_definition(action_type="process_refresh")
    required_roles = (
        [binding.role for binding in definition.bindings]
        if definition is not None
        else ["plan", "doc", "tasks"]
    )
    missing = [role for role in required_roles if role not in files_by_role]
    if missing:
        message = (
            f"Cannot automatically update process '{topic.name}': "
            f"missing {', '.join(missing)} file(s)."
        )
        proposal = create_process_refresh_skipped_proposal(topic, missing, message)
        return {
            "topic_id": topic.id,
            "skipped": True,
            "missing_types": missing,
            "proposal_id": proposal.id,
            "message": message,
        }

    plan_file = files_by_role["plan"]
    doc_file = files_by_role["doc"]
    tasks_file = files_by_role["tasks"]
    proposal = create_smart_process_update_proposal(
        topic,
        plan_file,
        doc_file,
        tasks_file,
    )
    return {
        "topic_id": topic.id,
        "skipped": False,
        "proposal_id": proposal.id,
        "source_file_ids": {
            "plan": plan_file.id,
            "doc": doc_file.id,
            "tasks": tasks_file.id,
        },
    }


def _maybe_create_companion_task(rule, run, topic, result):
    params = normalize_params(rule.params, rule.key, rule.action_type)
    scope = params.get("scope") or {}
    if not topic_in_scope(topic, scope):
        return None
    companion = companion_config(params) or {}
    if not companion or not companion.get("enabled", True):
        return None
    if run is None:
        return None

    flow_key = companion.get("flow_key", "process_update_review")
    payload = {
        "topic_id": topic.id,
        "topic_name": topic.name,
        "proposal_id": result.get("proposal_id"),
        "skipped": result.get("skipped", False),
    }
    title = companion_title(rule, topic)
    return create_companion_task(
        rule,
        run,
        flow_key=flow_key,
        payload=payload,
        title=title,
    )


def _resolve_scope_topics_from_params(params):
    scope = params.get("scope") or {}
    kind = scope.get("kind", "all")
    query = Topic.query.filter(Topic.archived_at.is_(None))
    if kind == "topic_type":
        return query.filter_by(type=scope.get("topic_type")).order_by(Topic.id).all()
    if kind == "topic":
        if scope.get("topic_id"):
            topic = db.session.get(Topic, int(scope["topic_id"]))
            return [topic] if topic else []
        if scope.get("topic_name"):
            topic = Topic.query.filter_by(name=scope["topic_name"]).first()
            return [topic] if topic else []
    return []


def _resolve_topic_from_context(context, params):
    topic = context.get("topic")
    if topic is not None:
        return topic
    topic_id = params.get("topic_id")
    if topic_id:
        topic = db.session.get(Topic, int(topic_id))
    else:
        topic = Topic.query.filter_by(name=params.get("topic_name", "main")).first()
    if topic is None:
        raise ValueError("topic not found")
    return topic


def _create_file(topic, name, file_type, is_main=True, order_index=None, create_defaults=True):
    if order_index is None:
        order_index = _next_file_order(topic.id)
    file = File(
        topic_id=topic.id,
        name=name,
        type=file_type,
        order_index=order_index,
        is_main=is_main,
    )
    db.session.add(file)
    db.session.flush()
    if create_defaults:
        for index, (block_type, content) in enumerate(
            DEFAULT_BLOCKS.get(file_type, DEFAULT_BLOCKS["text"])
        ):
            db.session.add(
                Block(
                    file_id=file.id,
                    type=block_type,
                    content=content,
                    order_index=index,
                )
            )
    db.session.flush()
    return file


def _next_file_order(topic_id):
    last = (
        File.query.filter_by(topic_id=topic_id)
        .order_by(File.order_index.desc(), File.id.desc())
        .first()
    )
    if last is None or last.order_index is None:
        return 0
    return last.order_index + 1
