from datetime import datetime

from models import AiProposal, File, db
from services.file_ai_mapper import (
    build_deltas,
    detect_language,
    flatten_process_files_for_ai,
    merge_segments,
    segments_from_ai_payload,
    segments_from_file,
    apply_segments_to_file,
)
from services.openai_service import chat_json


SMART_PROCESS_UPDATE_PROMPT = (
    "You are updating a personal process. Read the plan first, then the documentation "
    "from recently. Offer a new plan version similar to the original but with changes "
    "considering the docs. Only critical changes, and the plan should stay practical "
    "and concise. Afterwards go over the tasks file and update according to the plan. "
    "Respond in the same language as the input files."
)

SMART_PROCESS_UPDATE_SCHEMA = (
    "Return JSON with this shape: "
    '{"plan": {"segments": [{"type": "text|header|summary|list|table", "content": {...}, '
    '"label": "readable text"}], '
    '"tasks": {"segments": [{"type": "text|header|task|list", "content": {...}, '
    '"label": "readable text"}]}}. '
    "For tasks use type task with content {\"title\": \"...\"}. "
    "For list use content {\"items\": [{\"text\": \"...\"}]}. "
    "For table use content {\"rows\": [[\"cell\"]]}. "
    "For text/header/summary use content {\"text\": \"...\"}."
)


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
        f"{SMART_PROCESS_UPDATE_PROMPT} {lang_note} {SMART_PROCESS_UPDATE_SCHEMA}",
        user_prompt,
    )

    old_plan_segments = segments_from_file(plan_file.id)
    old_tasks_segments = segments_from_file(tasks_file.id)
    new_plan_segments = segments_from_ai_payload(
        (ai_result.get("plan") or {}).get("segments")
    )
    new_tasks_segments = segments_from_ai_payload(
        (ai_result.get("tasks") or {}).get("segments")
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
        "original_segments": {
            "plan": old_plan_segments,
            "tasks": old_tasks_segments,
        },
        "deltas": {
            "plan": build_deltas(old_plan_segments, new_plan_segments),
            "tasks": build_deltas(old_tasks_segments, new_tasks_segments),
        },
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
    original_segments = payload.get("original_segments") or {}
    deltas = payload.get("deltas") or {}
    topic_id = proposal.topic_id

    plan_source = _get_file(source_files.get("plan", {}).get("id"))
    doc_source = _get_file(source_files.get("doc", {}).get("id"))
    tasks_source = _get_file(source_files.get("tasks", {}).get("id"))
    if plan_source is None or doc_source is None or tasks_source is None:
        raise ValueError("source files no longer exist")

    plan_decisions = (decisions or {}).get("plan") or {}
    tasks_decisions = (decisions or {}).get("tasks") or {}

    final_plan = merge_segments(
        original_segments.get("plan") or [],
        deltas.get("plan") or [],
        plan_decisions,
    )
    final_tasks = merge_segments(
        original_segments.get("tasks") or [],
        deltas.get("tasks") or [],
        tasks_decisions,
    )

    now = datetime.utcnow()
    for file in (plan_source, doc_source, tasks_source):
        file.archived_at = now

    plan_file = _create_refresh_file(
        topic_id,
        name=plan_source.name,
        file_type="plan",
        order_index=plan_source.order_index,
        create_defaults=False,
    )
    doc_file = _create_refresh_file(
        topic_id,
        name=doc_source.name,
        file_type="doc",
        order_index=doc_source.order_index,
        create_defaults=False,
    )
    tasks_file = _create_refresh_file(
        topic_id,
        name=tasks_source.name,
        file_type="tasks",
        order_index=tasks_source.order_index,
        create_defaults=False,
    )

    apply_segments_to_file(plan_file, final_plan)
    _create_empty_doc_table(doc_file)
    apply_segments_to_file(tasks_file, final_tasks)

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


def _create_refresh_file(topic_id, name, file_type, order_index, create_defaults):
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
    if create_defaults:
        from services.automation_actions import DEFAULT_BLOCKS

        for index, (block_type, content) in enumerate(
            DEFAULT_BLOCKS.get(file_type, DEFAULT_BLOCKS["text"])
        ):
            from models import Block

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
