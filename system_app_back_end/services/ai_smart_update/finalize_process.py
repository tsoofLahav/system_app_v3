"""Finalize process smart update proposals."""

from datetime import datetime

from models import Block, File, db
from services.unit_mapper import apply_units_to_file


def finalize_process_update(proposal, decisions):
    from services.diff_engine import merge_document

    if proposal.proposal_type != "process_smart_update":
        raise ValueError("proposal is not a process smart update")
    if proposal.status != "pending":
        raise ValueError("proposal is already decided")

    payload = proposal.payload or {}
    source_files = payload.get("source_files") or {}
    change_set = payload.get("change_set") or {}
    topic_id = proposal.topic_id

    plan_source = _get_file(source_files.get("plan", {}).get("id"))
    doc_source = _get_file(source_files.get("doc", {}).get("id"))
    tasks_source = _get_file(source_files.get("tasks", {}).get("id"))
    if plan_source is None or doc_source is None or tasks_source is None:
        raise ValueError("source files no longer exist")

    documents = {
        doc.get("key"): doc for doc in change_set.get("documents") or [] if doc.get("key")
    }
    plan_doc = documents.get("plan") or {}
    tasks_doc = documents.get("tasks") or {}

    final_plan_units = merge_document(
        plan_doc.get("units") or [],
        plan_doc.get("changes") or [],
        decisions or {},
    )
    final_tasks_units = merge_document(
        tasks_doc.get("units") or [],
        tasks_doc.get("changes") or [],
        decisions or {},
    )

    now = datetime.utcnow()
    for file in (plan_source, doc_source, tasks_source):
        file.archived_at = now

    plan_file = _create_refresh_file(
        topic_id,
        name=plan_source.name,
        file_type="plan",
        order_index=plan_source.order_index,
    )
    doc_file = _create_refresh_file(
        topic_id,
        name=doc_source.name,
        file_type="doc",
        order_index=doc_source.order_index,
    )
    tasks_file = _create_refresh_file(
        topic_id,
        name=tasks_source.name,
        file_type="tasks",
        order_index=tasks_source.order_index,
    )

    apply_units_to_file(plan_file, final_plan_units)
    _create_empty_doc_table(doc_file)
    apply_units_to_file(tasks_file, final_tasks_units)

    proposal.status = "approved"
    proposal.decided_at = datetime.utcnow()
    proposal.payload = {
        **payload,
        "decisions": decisions,
        "created_file_ids": {
            "plan": plan_file.id,
            "doc": doc_file.id,
            "tasks": tasks_file.id,
        },
        "archived_file_ids": [plan_source.id, doc_source.id, tasks_source.id],
    }
    db.session.flush()
    return proposal


def _get_file(file_id):
    if not file_id:
        return None
    return db.session.get(File, int(file_id))


def _create_refresh_file(topic_id, name, file_type, order_index):
    from models import Topic

    topic = db.session.get(Topic, topic_id)
    if topic is None:
        raise ValueError("topic not found")

    file = File(
        topic_id=topic.id,
        name=name,
        type=file_type,
        order_index=order_index,
        is_main=True,
    )
    db.session.add(file)
    db.session.flush()
    return file


def _create_empty_doc_table(doc_file):
    db.session.add(
        Block(
            file_id=doc_file.id,
            type="table",
            content={"rows": [["", ""], ["", ""]]},
            order_index=0,
        )
    )
    db.session.flush()
