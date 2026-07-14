"""Finalize project smart update proposals (in-place part edits)."""

from __future__ import annotations

from datetime import datetime

from models import Block, File, Part, db
from services.diff_engine import merge_document
from services.doc_table_rows import insert_row_into_table_block
from services.part_placement import create_part_for_topic, place_part_in_file
from services.part_resolver import part_by_id
from services.unit_mapper import apply_units_to_part_in_file


def finalize_project_update(proposal, decisions):
    if proposal.proposal_type != "project_smart_update":
        raise ValueError("proposal is not a project smart update")
    if proposal.status != "pending":
        raise ValueError("proposal is already decided")

    payload = proposal.payload or {}
    source_files = payload.get("source_files") or {}
    change_set = payload.get("change_set") or {}
    topic_id = proposal.topic_id

    plan_file = _get_file(source_files.get("plan", {}).get("id"))
    execution_file = _get_file(source_files.get("execution", {}).get("id"))
    tasks_file = _get_file(source_files.get("tasks", {}).get("id"))
    doc_file = _get_file(source_files.get("doc", {}).get("id"))
    if plan_file is None or execution_file is None or tasks_file is None or doc_file is None:
        raise ValueError("source files no longer exist")

    applied_part_ids = []
    for part_entry in change_set.get("parts") or []:
        part_id = part_entry.get("part_id")
        part_name = part_entry.get("part_name") or "Part"
        is_new = bool(part_entry.get("is_new"))
        documents = part_entry.get("documents") or []

        if is_new:
            part = _ensure_part(topic_id, part_id, part_name)
            part_id = part.id
            _place_new_part_content(
                topic_id=topic_id,
                part=part,
                plan_file=plan_file,
                execution_file=execution_file,
                tasks_file=tasks_file,
                documents=documents,
                decisions=decisions or {},
            )
        else:
            part_id = int(part_id)
            for doc in documents:
                key = doc.get("key")
                target = {
                    "plan": plan_file,
                    "execution": execution_file,
                    "tasks": tasks_file,
                }.get(key)
                if target is None:
                    continue
                merged = merge_document(
                    doc.get("units") or [],
                    doc.get("changes") or [],
                    decisions or {},
                )
                if merged:
                    apply_units_to_part_in_file(target, part_id, merged)
        applied_part_ids.append(part_id)

    doc_rows_added = _apply_doc_append(doc_file, change_set.get("doc_append") or {})

    log_file = _get_file(source_files.get("log", {}).get("id"))
    if log_file is not None:
        log_file.is_main = False

    proposal.status = "approved"
    proposal.decided_at = datetime.utcnow()
    proposal.payload = {
        **payload,
        "decisions": decisions,
        "applied_part_ids": applied_part_ids,
        "doc_rows_added": doc_rows_added,
    }
    db.session.flush()
    return proposal


def _ensure_part(topic_id: int, part_id, part_name: str) -> Part:
    if part_id is not None:
        existing = part_by_id(int(part_id))
        if existing is not None and existing.topic_id == topic_id:
            return existing
    from models import Topic

    topic = db.session.get(Topic, topic_id)
    result = create_part_for_topic(topic, name=part_name)
    return db.session.get(Part, int(result["part"]["id"]))


def _place_new_part_content(
    *,
    topic_id,
    part,
    plan_file,
    execution_file,
    tasks_file,
    documents,
    decisions,
):
    from models import Topic

    topic = db.session.get(Topic, topic_id)
    files = [plan_file, execution_file, tasks_file]
    for file in files:
        place_part_in_file(file, part=part)

    for doc in documents:
        key = doc.get("key")
        target = {
            "plan": plan_file,
            "execution": execution_file,
            "tasks": tasks_file,
        }.get(key)
        if target is None:
            continue
        merged = merge_document(
            doc.get("units") or [],
            doc.get("changes") or [],
            decisions,
        )
        content_units = [u for u in merged if (u.get("text") or "").strip()]
        if content_units:
            apply_units_to_part_in_file(target, part.id, content_units)


def _apply_doc_append(doc_file, doc_append: dict) -> int:
    rows = doc_append.get("rows") or []
    if not rows:
        return 0

    table_block = (
        Block.query.filter_by(file_id=doc_file.id)
        .filter(Block.archived_at.is_(None))
        .filter(Block.type == "table")
        .order_by(Block.order_index, Block.id)
        .first()
    )
    if table_block is None:
        table_block = Block(
            file_id=doc_file.id,
            type="table",
            content={"rows": [["Date", "Entry"], ["", ""]]},
            order_index=0,
        )
        db.session.add(table_block)
        db.session.flush()

    count = 0
    for row in rows:
        text = (row.get("text") or "").strip()
        if not text:
            continue
        entry_date = (row.get("date") or "").strip()
        insert_row_into_table_block(table_block, entry_date, text)
        count += 1
    db.session.flush()
    return count


def _get_file(file_id):
    if not file_id:
        return None
    return db.session.get(File, int(file_id))
