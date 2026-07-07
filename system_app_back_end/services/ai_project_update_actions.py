"""Project update AI — split into focused steps (plan → execution → tasks → doc)."""

from __future__ import annotations

from datetime import date

from config import OPENAI_PROCESS_UPDATE_TEMPERATURE
from models import AiProposal, db
from services.diff_engine import (
    build_change_set,
    build_doc_row_change_set,
    build_document_change_set,
)
from services.openai_service import chat_json
from services.unit_mapper import (
    detect_language,
    flatten_project_files_for_ai,
    units_from_doc_table,
    units_from_file,
)

# --- Step 1: Plan + part mapping -------------------------------------------------

PROJECT_UPDATE_PLAN_PROMPT = """You analyze a project daily log against the project PLAN.

## Files

INPUT — Daily log (read only). What happened on a certain day: progress, decisions, issues, future points.

PLAN — Inner headers are project **parts**. Each part has a concise essence (list items and text under that header).

## Your job (step 1 of 4)

1. Read PLAN headers to learn the existing parts.
2. Read INPUT and map its content to part(s) — usually one primary part; side comments on others are possible.
3. First try to fit the log into **existing** parts. If the content clearly belongs to a new area of the project, add a new part (new header and essence) via plan_ops.
4. Return plan edits when a part must be added, removed, or its essence renamed/changed at the header or part-level summary — not for execution-level detail.

Set `plan_structure_changed` true when parts are added, removed, or renamed/redefined at the plan level (including new parts).

## Output

JSON only:
{
  "parts_touched": ["Part name"],
  "primary_part": "Part name",
  "input_summary": "1-3 sentences: what the log says, mapped to parts",
  "plan_structure_changed": false,
  "plan_ops": []
}

`plan_ops` entries (when needed):
- op: "replace" | "remove" | "add_after"
- unit_id: from PLAN input (use the last header or list item in a part as anchor for add_after when adding a new part section)
- text: full new line for replace/add_after — for a new part, the text is the new header title; follow with essence lines as needed via further add_after ops

New parts are valid when INPUT clearly does not fit any existing part. Do not force-fit unrelated content into the wrong part."""

# --- Step 2: Execution -----------------------------------------------------------

PROJECT_UPDATE_EXECUTION_PROMPT = """You update project EXECUTION from a daily log.

## Context

You receive which parts the log concerns and a short summary from step 1.

## Files

INPUT — Daily log (read only).

EXECUTION — Durable concrete work points under the same part headers as PLAN.
- No dates, no diary narrative, no exertion detail.
- State what the project needs / what is true going forward — not "today we did X".

## Your job (step 2 of 4)

Using INPUT and the part mapping, return edits to EXECUTION only.

Before adding a new point, check existing points in the relevant part. If INPUT overlaps a similar existing point, **replace** or refine that unit first to avoid near-duplicates. Add new points when the content is genuinely distinct.

Removing or merging points is fine when it reduces redundancy.

## Output

JSON only:
{"execution_ops":[]}

Each op:
- op: "replace" | "remove" | "add_after"
- unit_id: from EXECUTION input
- text: full new line

Use replace to update similar existing points; use add_after for clearly new durable points under the right part."""

# --- Step 3: Tasks -------------------------------------------------------------

PROJECT_UPDATE_TASKS_PROMPT = """You update project TASKS from a daily log.

## Context

You receive which parts the log concerns, a short summary, and the proposed EXECUTION changes from step 2.

## Files

INPUT — Daily log (read only).

TASKS — Calendar-sized missions under part headers. Simpler phrasing than execution.

## Rules

- Tasks are for organizing work the user can schedule — not a dump of every bullet.
- Group related small points into one task when they belong together and are not too large.
- Align with execution intent but phrase more simply and actionably.
- Avoid many tiny tasks.

## Your job (step 3 of 4)

Return edits to TASKS only.

## Output

JSON only:
{"tasks_ops":[]}

Each op:
- op: "replace" | "remove" | "add_after"
- unit_id: from TASKS input (e.g. task:12) or list item id
- text: full new task title / line

If execution changes imply new work but no matching task exists, use add_after on a sensible anchor in the same part."""

# --- Step 4: Documentation -----------------------------------------------------

PROJECT_UPDATE_DOC_PROMPT = """You add documentation rows from a project daily log.

## Files

INPUT — Daily log (read only).

DOCUMENTATION — Existing doc table (read only). Historical record by date.

## Your job (step 4 of 4)

Extract **important dated highlights** from INPUT for the documentation table.
- Multiple rows for the same date are allowed.
- Infer the date from the log when stated; otherwise use the date mentioned in the user message.
- Write concise entry text — what happened that day worth remembering (decisions, milestones, blockers). Not execution-level detail.

## Output

JSON only:
{"doc_ops":[]}

Each entry:
- date: YYYY-MM-DD
- text: entry text (no date prefix in text)"""


def _lang_note(locale: str) -> str:
    return "Respond in Hebrew." if locale == "he" else "Respond in English."


def _format_ops_for_context(ops: list) -> str:
    if not ops:
        return "(none)"
    lines = []
    for op in ops:
        action = op.get("op", "")
        unit_id = op.get("unit_id", "")
        text = (op.get("text") or "").strip()
        lines.append(f"- {action} {unit_id}: {text}")
    return "\n".join(lines)


def _run_plan_step(topic_name: str, flattened: dict, locale: str) -> dict:
    user_prompt = (
        f"Topic: {topic_name}\n\n"
        f"{flattened['input']}\n\n"
        f"{flattened['plan']}"
    )
    return chat_json(
        f"{PROJECT_UPDATE_PLAN_PROMPT}\n\n{_lang_note(locale)}",
        user_prompt,
        temperature=OPENAI_PROCESS_UPDATE_TEMPERATURE,
    )


def _run_execution_step(
    topic_name: str, flattened: dict, plan_result: dict, locale: str
) -> dict:
    parts_touched = plan_result.get("parts_touched") or []
    primary = plan_result.get("primary_part") or ""
    summary = (plan_result.get("input_summary") or "").strip()
    user_prompt = (
        f"Topic: {topic_name}\n"
        f"Parts touched: {', '.join(parts_touched) or primary or 'General'}\n"
        f"Primary part: {primary or 'General'}\n"
        f"Input summary: {summary or '(see INPUT below)'}\n\n"
        f"{flattened['input']}\n\n"
        f"{flattened['execution']}"
    )
    return chat_json(
        f"{PROJECT_UPDATE_EXECUTION_PROMPT}\n\n{_lang_note(locale)}",
        user_prompt,
        temperature=OPENAI_PROCESS_UPDATE_TEMPERATURE,
    )


def _run_tasks_step(
    topic_name: str,
    flattened: dict,
    plan_result: dict,
    execution_result: dict,
    locale: str,
) -> dict:
    parts_touched = plan_result.get("parts_touched") or []
    primary = plan_result.get("primary_part") or ""
    summary = (plan_result.get("input_summary") or "").strip()
    execution_ops = execution_result.get("execution_ops") or []
    user_prompt = (
        f"Topic: {topic_name}\n"
        f"Parts touched: {', '.join(parts_touched) or primary or 'General'}\n"
        f"Primary part: {primary or 'General'}\n"
        f"Input summary: {summary or '(see INPUT below)'}\n\n"
        f"Proposed execution changes:\n"
        f"{_format_ops_for_context(execution_ops)}\n\n"
        f"{flattened['input']}\n\n"
        f"{flattened['tasks']}"
    )
    return chat_json(
        f"{PROJECT_UPDATE_TASKS_PROMPT}\n\n{_lang_note(locale)}",
        user_prompt,
        temperature=OPENAI_PROCESS_UPDATE_TEMPERATURE,
    )


def _run_doc_step(
    topic_name: str, flattened: dict, log_date_hint: str, locale: str
) -> dict:
    user_prompt = (
        f"Topic: {topic_name}\n"
        f"Default date if not in log: {log_date_hint}\n\n"
        f"{flattened['input']}\n\n"
        f"{flattened['documentation']}"
    )
    return chat_json(
        f"{PROJECT_UPDATE_DOC_PROMPT}\n\n{_lang_note(locale)}",
        user_prompt,
        temperature=OPENAI_PROCESS_UPDATE_TEMPERATURE,
    )


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

    log_date_hint = date.today().isoformat()

    plan_result = _run_plan_step(topic.name, flattened, locale)
    execution_result = _run_execution_step(
        topic.name, flattened, plan_result, locale
    )
    tasks_result = _run_tasks_step(
        topic.name, flattened, plan_result, execution_result, locale
    )
    doc_result = _run_doc_step(topic.name, flattened, log_date_hint, locale)

    ai_result = {
        "parts_touched": plan_result.get("parts_touched") or [],
        "primary_part": plan_result.get("primary_part"),
        "input_summary": plan_result.get("input_summary"),
        "plan_structure_changed": bool(plan_result.get("plan_structure_changed")),
        "plan_ops": plan_result.get("plan_ops") or [],
        "execution_ops": execution_result.get("execution_ops") or [],
        "tasks_ops": tasks_result.get("tasks_ops") or [],
        "doc_ops": doc_result.get("doc_ops") or [],
    }

    change_set = build_project_update_change_set(
        plan_file,
        execution_file,
        tasks_file,
        doc_file,
        ai_result,
    )

    return {
        "locale": locale,
        "plan_structure_changed": ai_result["plan_structure_changed"],
        "ai_steps": {
            "plan": plan_result,
            "execution": execution_result,
            "tasks": tasks_result,
            "doc": doc_result,
        },
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
