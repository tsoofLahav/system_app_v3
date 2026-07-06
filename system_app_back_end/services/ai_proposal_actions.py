from datetime import datetime

from config import OPENAI_PROCESS_UPDATE_TEMPERATURE
from models import AiProposal, File, db
from services.diff_engine import (
    build_change_set,
    build_doc_row_change_set,
    build_document_change_set,
    merge_document,
)
from services.doc_table_rows import insert_row_into_table_block
from services.openai_service import chat_json
from services.project_part_sync import sync_execution_and_tasks_to_plan
from services.unit_mapper import (
    apply_units_to_file,
    detect_language,
    flatten_process_files_for_ai,
    flatten_project_files_for_ai,
    units_from_doc_table,
    units_from_file,
)


SMART_PROCESS_UPDATE_PROMPT = """You update a personal process from weekly documentation.

## Files

PLAN — Concise guide: purpose, principles, durable conclusions. Prefer editing existing points over adding new ones. You may remove or merge points when it keeps the plan more organized and concise without losing important information.

TASKS — Recurring practical actions from the plan (daily, weekly, every X days, etc.). Specific wording, aligned with the plan.

DOCUMENTATION — User notes (read only). May state routine changes explicitly or only imply them. Infer justified updates from these notes.

## What to do

1. Read PLAN, then DOCUMENTATION, then TASKS.
2. Decide what in PLAN and TASKS should change based on the documentation.
3. Return only edits to existing units, using the unit IDs provided.

For each edit, `text` is the new line as it should appear in the file — a direct replacement for that unit, not a suggestion about what to do.

## Output

JSON only:
{"plan_ops":[],"tasks_ops":[]}

Each op:
- op: "replace" | "remove" | "add_after"
- unit_id: from PLAN or TASKS input
- text: required for replace and add_after — the full new line

Prefer replace and edit over remove and add. Use remove or merge when it helps the plan stay organized and concise. Use add_after only when a new point is clearly needed.

## Examples

Plan unit: [block:3:item:1] Practice 3 minutes daily
Doc: practice feels too short; 5 min works better
→ {"op":"replace","unit_id":"block:3:item:1","text":"Practice 5 minutes daily"}

Tasks unit: [task:12] Evening stretch routine
Plan now emphasizes morning mobility
→ {"op":"replace","unit_id":"task:12","text":"Morning mobility routine (10 min)"}

Respond in the same language as the input files."""


SMART_PROJECT_UPDATE_PROMPT = """You update a project from a daily log the user finished editing.

## Files

INPUT — Daily log (read only). Describes what happened on a certain day: progress, decisions, issues, future points.

PLAN — Inner headers are project parts (sections). Each part has a concise essence. Edit only when a part must be added, removed, or its essence changed.

EXECUTION — Concrete durable work points grouped under the same part headers. No dates, no narrative of what was done on a specific day, no exertion detail.

TASKS — Calendar-sized missions under the same part headers. Simpler phrasing than execution. Group related small points into one task when they belong together and are not too large.

DOCUMENTATION — Historical table (read only). Propose new dated rows for important events from the input.

## What to do

1. Read PLAN headers to understand parts. Read INPUT and map content to relevant part(s).
2. Decide execution, task, documentation, and rare plan changes.
3. Return only concrete edits using unit IDs from PLAN, EXECUTION, and TASKS.

Execution text must be durable project state — not a diary entry.
Documentation rows capture dated highlights from the input.
Tasks should be respectful mission size — avoid many tiny tasks.

Set plan_structure_changed true only when adding, removing, or renaming a part essence in PLAN.

## Output

JSON only:
{"plan_structure_changed":false,"plan_ops":[],"execution_ops":[],"tasks_ops":[],"doc_ops":[]}

plan_ops / execution_ops / tasks_ops entries:
- op: "replace" | "remove" | "add_after"
- unit_id: from the matching file input
- text: required for replace and add_after

doc_ops entries:
- date: YYYY-MM-DD
- text: entry text

Respond in the same language as the input files."""


def smart_process_update(topic, plan_file, doc_file, tasks_file):
    flattened = flatten_process_files_for_ai(plan_file, doc_file, tasks_file)
    locale = detect_language(
        flattened["plan"],
        flattened["documentation"],
        flattened["tasks"],
    )
    lang_note = "Respond in Hebrew." if locale == "he" else "Respond in English."

    user_prompt = (
        f"Topic: {topic.name}\n\n"
        f"{flattened['plan']}\n\n"
        f"{flattened['documentation']}\n\n"
        f"{flattened['tasks']}"
    )

    ai_result = chat_json(
        f"{SMART_PROCESS_UPDATE_PROMPT}\n\n{lang_note}",
        user_prompt,
        temperature=OPENAI_PROCESS_UPDATE_TEMPERATURE,
    )

    plan_units = units_from_file(plan_file.id)
    tasks_units = units_from_file(tasks_file.id)
    plan_ops = ai_result.get("plan_ops") or []
    tasks_ops = ai_result.get("tasks_ops") or []

    if not tasks_ops and _doc_implies_task_changes(flattened["documentation"]):
        retry = chat_json(
            f"{SMART_PROCESS_UPDATE_PROMPT}\n\n{lang_note}\n"
            "The tasks file must be updated. Return tasks_ops only in JSON: "
            '{"tasks_ops":[]}',
            f"{flattened['tasks']}\n\nRevised plan context:\n"
            f"{flattened['plan']}\n\nDocumentation:\n{flattened['documentation']}",
            temperature=OPENAI_PROCESS_UPDATE_TEMPERATURE,
        )
        tasks_ops = retry.get("tasks_ops") or tasks_ops

    change_set = build_change_set(
        [
            build_document_change_set("plan", plan_file.name, plan_units, plan_ops),
            build_document_change_set(
                "tasks", tasks_file.name, tasks_units, tasks_ops
            ),
        ]
    )

    return {
        "locale": locale,
        "source_files": {
            "plan": {"id": plan_file.id, "name": plan_file.name, "type": plan_file.type},
            "doc": {"id": doc_file.id, "name": doc_file.name, "type": doc_file.type},
            "tasks": {
                "id": tasks_file.id,
                "name": tasks_file.name,
                "type": tasks_file.type,
            },
        },
        "change_set": change_set,
    }


def create_smart_process_update_proposal(topic, plan_file, doc_file, tasks_file):
    payload = smart_process_update(topic, plan_file, doc_file, tasks_file)
    proposal = AiProposal(
        topic_id=topic.id,
        target_file_id=None,
        proposal_type="process_smart_update",
        payload=payload,
        status="pending",
    )
    db.session.add(proposal)
    db.session.flush()
    return proposal


def create_process_refresh_skipped_proposal(topic, missing_types, message):
    proposal = AiProposal(
        topic_id=topic.id,
        target_file_id=None,
        proposal_type="process_refresh_skipped",
        payload={
            "missing_types": missing_types,
            "message": message,
        },
        status="pending",
    )
    db.session.add(proposal)
    db.session.flush()
    return proposal


def finalize_process_update(proposal, decisions):
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


def _doc_implies_task_changes(documentation_text):
    lowered = (documentation_text or "").lower()
    hints = ("task", "todo", "משימ", "לעשות", "צריך", "need to", "should", "routine")
    return any(hint in lowered for hint in hints)


def _get_file(file_id):
    if not file_id:
        return None
    return db.session.get(File, int(file_id))


def _create_refresh_file(topic_id, name, file_type, order_index, is_main=True):
    from models import Topic

    topic = db.session.get(Topic, topic_id)
    if topic is None:
        raise ValueError("topic not found")

    file = File(
        topic_id=topic.id,
        name=name,
        type=file_type,
        order_index=order_index,
        is_main=is_main,
    )
    db.session.add(file)
    db.session.flush()
    return file


    db.session.flush()


def build_project_update_change_set(
    plan_file,
    execution_file,
    tasks_file,
    doc_file,
    ai_result,
):
    plan_units = units_from_file(plan_file.id)
    execution_units = units_from_file(execution_file.id)
    tasks_units = units_from_file(tasks_file.id)
    doc_units = units_from_doc_table(doc_file)

    documents = []
    plan_ops = ai_result.get("plan_ops") or []
    execution_ops = ai_result.get("execution_ops") or []
    tasks_ops = ai_result.get("tasks_ops") or []
    doc_ops = ai_result.get("doc_ops") or []

    if plan_ops:
        documents.append(
            build_document_change_set(
                "plan", plan_file.name, plan_units, plan_ops
            )
        )
    if execution_ops:
        documents.append(
            build_document_change_set(
                "execution", execution_file.name, execution_units, execution_ops
            )
        )
    if tasks_ops:
        documents.append(
            build_document_change_set(
                "tasks", tasks_file.name, tasks_units, tasks_ops
            )
        )
    if doc_ops:
        documents.append(
            build_doc_row_change_set("doc", doc_file.name, doc_units, doc_ops)
        )

    return build_change_set(documents)


def smart_project_update(
    topic,
    input_file,
    plan_file,
    execution_file,
    tasks_file,
    doc_file,
):
    flattened = flatten_project_files_for_ai(
        input_file, plan_file, execution_file, tasks_file, doc_file
    )
    locale = detect_language(
        flattened["input"],
        flattened["plan"],
        flattened["execution"],
        flattened["tasks"],
        flattened["documentation"],
    )
    lang_note = "Respond in Hebrew." if locale == "he" else "Respond in English."

    user_prompt = (
        f"Topic: {topic.name}\n\n"
        f"{flattened['input']}\n\n"
        f"{flattened['plan']}\n\n"
        f"{flattened['execution']}\n\n"
        f"{flattened['tasks']}\n\n"
        f"{flattened['documentation']}"
    )

    ai_result = chat_json(
        f"{SMART_PROJECT_UPDATE_PROMPT}\n\n{lang_note}",
        user_prompt,
        temperature=OPENAI_PROCESS_UPDATE_TEMPERATURE,
    )

    change_set = build_project_update_change_set(
        plan_file,
        execution_file,
        tasks_file,
        doc_file,
        ai_result,
    )

    return {
        "locale": locale,
        "plan_structure_changed": bool(ai_result.get("plan_structure_changed")),
        "source_files": {
            "input": {
                "id": input_file.id,
                "name": input_file.name,
                "type": input_file.type,
            },
            "plan": {"id": plan_file.id, "name": plan_file.name, "type": plan_file.type},
            "execution": {
                "id": execution_file.id,
                "name": execution_file.name,
                "type": execution_file.type,
            },
            "tasks": {
                "id": tasks_file.id,
                "name": tasks_file.name,
                "type": tasks_file.type,
            },
            "doc": {"id": doc_file.id, "name": doc_file.name, "type": doc_file.type},
        },
        "change_set": change_set,
    }


def create_smart_project_update_proposal(
    topic,
    input_file,
    plan_file,
    execution_file,
    tasks_file,
    doc_file,
):
    payload = smart_project_update(
        topic,
        input_file,
        plan_file,
        execution_file,
        tasks_file,
        doc_file,
    )
    proposal = AiProposal(
        topic_id=topic.id,
        target_file_id=None,
        proposal_type="project_smart_update",
        payload=payload,
        status="pending",
    )
    db.session.add(proposal)
    db.session.flush()
    return proposal


def create_project_update_skipped_proposal(topic, missing_types, message):
    proposal = AiProposal(
        topic_id=topic.id,
        target_file_id=None,
        proposal_type="project_update_skipped",
        payload={
            "missing_types": missing_types,
            "message": message,
        },
        status="pending",
    )
    db.session.add(proposal)
    db.session.flush()
    return proposal


def finalize_project_update(proposal, decisions):
    if proposal.proposal_type != "project_smart_update":
        raise ValueError("proposal is not a project smart update")
    if proposal.status != "pending":
        raise ValueError("proposal is already decided")

    payload = proposal.payload or {}
    source_files = payload.get("source_files") or {}
    change_set = payload.get("change_set") or {}
    topic_id = proposal.topic_id
    plan_structure_changed = bool(payload.get("plan_structure_changed"))

    plan_source = _get_file(source_files.get("plan", {}).get("id"))
    execution_source = _get_file(source_files.get("execution", {}).get("id"))
    tasks_source = _get_file(source_files.get("tasks", {}).get("id"))
    doc_source = _get_file(source_files.get("doc", {}).get("id"))
    if (
        plan_source is None
        or execution_source is None
        or tasks_source is None
        or doc_source is None
    ):
        raise ValueError("source files no longer exist")

    documents = {
        doc.get("key"): doc for doc in change_set.get("documents") or [] if doc.get("key")
    }

    final_plan_units = merge_document(
        (documents.get("plan") or {}).get("units") or units_from_file(plan_source.id),
        (documents.get("plan") or {}).get("changes") or [],
        decisions or {},
    )
    final_execution_units = merge_document(
        (documents.get("execution") or {}).get("units")
        or units_from_file(execution_source.id),
        (documents.get("execution") or {}).get("changes") or [],
        decisions or {},
    )
    final_tasks_units = merge_document(
        (documents.get("tasks") or {}).get("units") or units_from_file(tasks_source.id),
        (documents.get("tasks") or {}).get("changes") or [],
        decisions or {},
    )

    doc_changes = (documents.get("doc") or {}).get("changes") or []
    accepted_doc_rows = [
        change
        for change in doc_changes
        if change.get("action") == "add_row" and _decision(decisions, change.get("id"))
    ]

    now = datetime.utcnow()
    archived_ids = []
    created_ids = {}

    if documents.get("plan"):
        plan_source.archived_at = now
        archived_ids.append(plan_source.id)
        plan_file = _create_refresh_file(
            topic_id,
            name=plan_source.name,
            file_type="plan",
            order_index=plan_source.order_index,
            is_main=plan_source.is_main,
        )
        apply_units_to_file(plan_file, final_plan_units)
        created_ids["plan"] = plan_file.id
    else:
        plan_file = plan_source

    if documents.get("execution"):
        execution_source.archived_at = now
        archived_ids.append(execution_source.id)
        execution_file = _create_refresh_file(
            topic_id,
            name=execution_source.name,
            file_type="execution",
            order_index=execution_source.order_index,
            is_main=execution_source.is_main,
        )
        apply_units_to_file(execution_file, final_execution_units)
        created_ids["execution"] = execution_file.id
    else:
        execution_file = execution_source

    if documents.get("tasks"):
        tasks_source.archived_at = now
        archived_ids.append(tasks_source.id)
        tasks_file = _create_refresh_file(
            topic_id,
            name=tasks_source.name,
            file_type="tasks",
            order_index=tasks_source.order_index,
            is_main=tasks_source.is_main,
        )
        apply_units_to_file(tasks_file, final_tasks_units)
        created_ids["tasks"] = tasks_file.id
    else:
        tasks_file = tasks_source

    if plan_structure_changed:
        sync_execution_and_tasks_to_plan(plan_file, execution_file, tasks_file)

    if accepted_doc_rows:
        table_block = _doc_table_block(doc_source)
        if table_block is not None:
            for change in accepted_doc_rows:
                insert_row_into_table_block(
                    table_block,
                    change.get("row_date") or "",
                    change.get("row_text") or change.get("new_text") or "",
                )

    proposal.status = "approved"
    proposal.decided_at = datetime.utcnow()
    proposal.payload = {
        **payload,
        "decisions": decisions,
        "created_file_ids": created_ids,
        "archived_file_ids": archived_ids,
    }
    db.session.flush()
    return proposal


def finalize_ai_proposal(proposal, decisions):
    if proposal.proposal_type == "process_smart_update":
        return finalize_process_update(proposal, decisions)
    if proposal.proposal_type == "project_smart_update":
        return finalize_project_update(proposal, decisions)
    raise ValueError(f"unsupported proposal type for finalize: {proposal.proposal_type}")


def _decision(decisions, change_id):
    if not decisions or change_id is None:
        return False
    if str(change_id) in decisions:
        return bool(decisions[str(change_id)])
    return bool(decisions.get(change_id))


def _doc_table_block(doc_file):
    from models import Block

    return (
        Block.query.filter_by(file_id=doc_file.id)
        .filter(Block.archived_at.is_(None))
        .filter_by(type="table")
        .order_by(Block.order_index, Block.id)
        .first()
    )


def _create_empty_doc_table(doc_file):
    from models import Block

    db.session.add(
        Block(
            file_id=doc_file.id,
            type="table",
            content={"rows": [["", ""], ["", ""]]},
            order_index=0,
        )
    )
    db.session.flush()
