from datetime import datetime

from models import Block, File, Task, Topic, db
from services.ai_proposal_actions import (
    create_process_refresh_skipped_proposal,
    create_smart_process_update_proposal,
)


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


def run_action(rule):
    action_type = rule.action_type
    params = rule.params or {}
    if action_type == "create_file_by_time":
        return create_file_by_time(params)
    if action_type == "archive_at_time":
        return archive_at_time(params)
    if action_type == "rotate_daily_main_file":
        return rotate_daily_main_file(params)
    if action_type == "weekly_process_refresh":
        return weekly_process_refresh(params)
    raise ValueError(f"Unknown automation action: {action_type}")


def create_file_by_time(params):
    topic = _resolve_topic(params)
    file = _create_file(
        topic,
        name=params.get("name", "Text"),
        file_type=params.get("type", "text"),
        is_main=params.get("is_main", True),
    )
    return {"created_file_id": file.id, "topic_id": topic.id}


def archive_at_time(params):
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


def rotate_daily_main_file(params):
    main = Topic.query.filter_by(name=params.get("topic_name", "main")).first()
    if main is None:
        raise ValueError("main topic not found")
    daily_name = params.get("name", "Daily")
    existing = (
        File.query.filter_by(topic_id=main.id, name=daily_name)
        .filter(File.archived_at.is_(None))
        .order_by(File.id.desc())
        .first()
    )
    if existing is not None:
        existing.archived_at = datetime.utcnow()
    file = _create_file(main, name=daily_name, file_type=params.get("type", "main"), is_main=True)
    return {
        "archived_file_id": existing.id if existing else None,
        "created_file_id": file.id,
    }


def weekly_process_refresh(params):
    processes = (
        Topic.query.filter_by(type="process")
        .filter(Topic.archived_at.is_(None))
        .order_by(Topic.id)
        .all()
    )
    refreshed = []
    for topic in processes:
        refreshed.append(_refresh_process(topic, params))
    return {"refreshed": refreshed}


def _refresh_process(topic, params):
    files_by_type = _process_files_by_type(topic.id)
    missing = [file_type for file_type in ("plan", "doc", "tasks") if file_type not in files_by_type]
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

    plan_file = files_by_type["plan"]
    doc_file = files_by_type["doc"]
    tasks_file = files_by_type["tasks"]
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


def _process_files_by_type(topic_id):
    files = (
        File.query.filter_by(topic_id=topic_id)
        .filter(File.type.in_(["plan", "doc", "tasks"]))
        .filter(File.archived_at.is_(None))
        .order_by(File.order_index, File.id)
        .all()
    )
    by_type = {}
    for file in files:
        by_type.setdefault(file.type, file)
    return by_type


def _resolve_topic(params):
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
        for index, (block_type, content) in enumerate(DEFAULT_BLOCKS.get(file_type, DEFAULT_BLOCKS["text"])):
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


def _default_name(file_type):
    return {
        "plan": "Plan",
        "doc": "Documentation",
        "tasks": "Tasks",
        "execution": "Execution",
        "overview": "Summary",
    }.get(file_type, "Text")
