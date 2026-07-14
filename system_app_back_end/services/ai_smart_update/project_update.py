"""Project smart update — part-aware orchestration."""

from __future__ import annotations

from config import OPENAI_PROCESS_UPDATE_TEMPERATURE
from services.ai_smart_update.change_set_builder import build_part_change_set
from services.ai_smart_update.doc_journey import generate_doc_journey_rows
from services.ai_smart_update.log_parser import log_file_date, parse_log_parts
from services.ai_smart_update.prompts import (
    OPS_OUTPUT_FORMAT,
    ROLE_EXECUTION,
    ROLE_LOG,
    ROLE_PLAN,
    ROLE_TASKS,
)
from services.ai_smart_update.unit_ops import normalize_ops
from services.diff_engine import build_document_change_set
from services.openai_service import chat_json
from services.part_resolver import files_containing_part
from services.unit_mapper import (
    detect_language,
    flatten_part_files_for_ai,
    units_for_part_in_file,
)

EXISTING_PART_PROMPT = f"""You update a project part from a work log.

## Files

{ROLE_PLAN}

{ROLE_EXECUTION}

{ROLE_TASKS}

{ROLE_LOG}

## What to do

1. Read the LOG, then current PLAN, EXECUTION, and TASKS for this part.
2. Decide what should change in each file based on the log.
3. Return only edits to existing units using the unit IDs provided.

## Output

{{"plan_ops":[],"execution_ops":[],"tasks_ops":[]}}

{OPS_OUTPUT_FORMAT}

Respond in the same language as the log."""

NEW_PART_PROMPT = f"""You create initial content for a new project part from a work log.

## Files

{ROLE_PLAN} — return bullet list items only.

{ROLE_EXECUTION} — return text paragraphs and sub-bullets elaborating the plan.

{ROLE_TASKS} — return actionable task lines.

{ROLE_LOG}

## Output

JSON only:
{{"plan_items":[],"execution_items":[],"task_items":[]}}

Each item is a string line as it should appear in the file. Respond in the same language as the log."""


def _prefix_changes(documents: list[dict], part_id: int | None) -> list[dict]:
    prefix = f"part:{part_id or 'new'}:"
    result = []
    for doc in documents:
        doc = dict(doc)
        changes = []
        for change in doc.get("changes") or []:
            change = dict(change)
            change["id"] = f"{prefix}{change['id']}"
            changes.append(change)
        doc["changes"] = changes
        result.append(doc)
    return result


def _new_part_to_documents(part_name: str, ai_result: dict) -> list[dict]:
    documents = []
    specs = [
        ("plan", "Plan", ai_result.get("plan_items") or [], "list_item"),
        ("execution", "Execution", ai_result.get("execution_items") or [], "list_item"),
        ("tasks", "Tasks", ai_result.get("task_items") or [], "task"),
    ]
    for key, title, items, kind in specs:
        units = []
        changes = []
        for index, text in enumerate(items):
            text = str(text).strip()
            if not text:
                continue
            change_id = f"{key}:c{index + 1}"
            units.append({"id": f"new:{change_id}", "kind": kind, "text": text})
            changes.append(
                {
                    "id": change_id,
                    "action": "add_after",
                    "unit_id": f"anchor:{key}",
                    "old_text": "",
                    "new_text": text,
                    "new_unit": {"id": f"new:{change_id}", "kind": kind, "text": text},
                }
            )
        if not units:
            units = [{"id": f"anchor:{key}", "kind": kind, "text": ""}]
        documents.append({"key": key, "title": title, "units": units, "changes": changes})
    return documents


def _update_existing_part(
    *,
    topic,
    part_id: int,
    part_name: str,
    log_text: str,
    plan_file,
    execution_file,
    tasks_file,
) -> list[dict]:
    plan_units = units_for_part_in_file(plan_file.id, part_id) if plan_file else []
    execution_units = (
        units_for_part_in_file(execution_file.id, part_id) if execution_file else []
    )
    tasks_units = units_for_part_in_file(tasks_file.id, part_id) if tasks_file else []

    flattened = flatten_part_files_for_ai(
        part_name=part_name,
        log_text=log_text,
        plan_units=plan_units,
        execution_units=execution_units,
        tasks_units=tasks_units,
    )
    locale = detect_language(log_text, flattened)
    lang_note = "Respond in Hebrew." if locale == "he" else "Respond in English."

    ai_result = chat_json(
        f"{EXISTING_PART_PROMPT}\n\n{lang_note}",
        f"Topic: {topic.name}\nPart: {part_name}\n\n{flattened}",
        temperature=OPENAI_PROCESS_UPDATE_TEMPERATURE,
    )

    docs = [
        build_document_change_set(
            "plan",
            plan_file.name if plan_file else "Plan",
            plan_units,
            normalize_ops(ai_result.get("plan_ops")),
        ),
        build_document_change_set(
            "execution",
            execution_file.name if execution_file else "Execution",
            execution_units,
            normalize_ops(ai_result.get("execution_ops")),
        ),
        build_document_change_set(
            "tasks",
            tasks_file.name if tasks_file else "Tasks",
            tasks_units,
            normalize_ops(ai_result.get("tasks_ops")),
        ),
    ]
    return _prefix_changes(docs, part_id)


def _create_new_part(*, topic, part_name: str, log_text: str) -> list[dict]:
    locale = detect_language(log_text)
    lang_note = "Respond in Hebrew." if locale == "he" else "Respond in English."
    ai_result = chat_json(
        f"{NEW_PART_PROMPT}\n\n{lang_note}",
        f"Topic: {topic.name}\nNew part: {part_name}\n\n=== LOG ===\n{log_text}",
        temperature=OPENAI_PROCESS_UPDATE_TEMPERATURE,
    )
    return _prefix_changes(_new_part_to_documents(part_name, ai_result), None)


def smart_project_update(topic, log_file, plan_file, execution_file, tasks_file, doc_file):
    sections = parse_log_parts(log_file, topic.id)
    if not sections:
        raise ValueError("Log file has no part content")

    part_payloads = []
    full_log_text = "\n\n".join(
        f"=== {s['part_name']} ===\n{s['log_text']}" for s in sections
    )

    for section in sections:
        part_id = section.get("part_id")
        part_name = section["part_name"]
        log_text = section["log_text"]
        is_new = section["is_new"] or (
            part_id is not None and "plan" not in files_containing_part(topic.id, part_id)
        )

        if is_new:
            documents = _create_new_part(
                topic=topic,
                part_name=part_name,
                log_text=log_text,
            )
            part_payloads.append(
                {
                    "part_id": part_id,
                    "part_name": part_name,
                    "is_new": True,
                    "documents": documents,
                }
            )
        else:
            documents = _update_existing_part(
                topic=topic,
                part_id=int(part_id),
                part_name=part_name,
                log_text=log_text,
                plan_file=plan_file,
                execution_file=execution_file,
                tasks_file=tasks_file,
            )
            part_payloads.append(
                {
                    "part_id": part_id,
                    "part_name": part_name,
                    "is_new": False,
                    "documents": documents,
                }
            )

    log_date = log_file_date(log_file)
    doc_rows = generate_doc_journey_rows(
        log_text=full_log_text,
        doc_file=doc_file,
        log_date=log_date,
    )

    change_set = build_part_change_set(
        log_file={
            "id": log_file.id,
            "name": log_file.name,
            "date": log_date,
        },
        parts=part_payloads,
        doc_append={"rows": doc_rows},
    )

    return {
        "locale": detect_language(full_log_text),
        "source_files": {
            "log": {"id": log_file.id, "name": log_file.name, "type": log_file.type},
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
