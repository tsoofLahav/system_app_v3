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
    annotate_units_with_parts,
    detect_language,
    flatten_project_files_for_ai,
    units_from_doc_table,
    units_from_file,
)

# --- Step 1: Plan + part mapping -------------------------------------------------

PROJECT_UPDATE_PLAN_PROMPT = """You analyze a project daily log against the project PLAN.

## Files (part-grouped)

Each file is split into **parts** marked by `--- PART: Name ---` headers.
`PART LIST` at the top lists existing part names only — do not invent parts that are not in PLAN unless INPUT requires a new one.

INPUT — Daily log (read only). May also use part sections if the user structured their log.

PLAN — Inner headers are project **parts**. Under each part: concise essence (list items and text).

## Your job (step 1 of 4)

1. Read `PART LIST` and each `--- PART: ... ---` block to learn existing parts.
2. Read INPUT and decide which part(s) the log belongs to.
3. **New part decision (important):**
   - If INPUT describes a clearly distinct project area that does **not** match any existing PLAN part → you **must** add a new part.
   - If INPUT only updates, refines, or extends work within an existing area → edit that existing part only.
   - Do **not** force unrelated INPUT into the wrong existing part to avoid adding a part.
4. Return plan edits when a part must be added, removed, or its essence renamed/changed — not for execution-level detail.

Set `plan_structure_changed` true when parts are added, removed, or renamed/redefined (including new parts).

## Output

JSON only:
{
  "existing_parts": ["Part A", "Part B"],
  "new_parts": [],
  "parts_touched": ["Part name"],
  "primary_part": "Part name",
  "input_summary": "1-3 sentences: what the log says, mapped to parts",
  "plan_structure_changed": false,
  "plan_ops": []
}

`new_parts`: names of parts you are **creating** that were not in PLAN `PART LIST`. Empty if only editing existing parts.

`plan_ops` entries (when needed):
- op: "replace" | "remove" | "add_after"
- unit_id: from PLAN input
- text: full new line
- kind: required for add_after when adding a **new part** — use `"header"` for the new part title; use `"list_item"` or `"paragraph"` for essence lines under that part

To add a new part at the end: `add_after` on the last unit of the last existing part (or last unit in file) with `kind: "header"` and `text` = new part name, then further `add_after` ops on that header for essence lines."""

# --- Step 2: Execution -----------------------------------------------------------

PROJECT_UPDATE_EXECUTION_PROMPT = """You update project EXECUTION from a daily log.

## Context

You receive which parts the log concerns, any **new parts** from step 1, and a short summary.

## Files (part-grouped)

Each section is marked `--- PART: Name ---`. Match edits to the correct part block.

INPUT — Daily log (read only).

EXECUTION — Durable concrete work points under the same part headers as PLAN.
- No dates, no diary narrative, no exertion detail.
- State what the project needs / what is true going forward — not "today we did X".

## Your job (step 2 of 4)

Using INPUT and the part mapping, return edits to EXECUTION only.

If step 1 added **new parts**, you must add matching `--- PART: ... ---` sections in EXECUTION:
- First `add_after` on the last unit of the last existing part (or last file unit) with `kind: "header"` and the new part name
- Then add durable points under that part via further `add_after` ops

Before adding a new point in an existing part, check existing points there. If INPUT overlaps a similar point, **replace** or refine that unit first. Add new points when genuinely distinct.

## Output

JSON only:
{"execution_ops":[]}

Each op:
- op: "replace" | "remove" | "add_after"
- unit_id: from EXECUTION input
- text: full new line
- kind: use `"header"` when adding a new part section; otherwise omit or use list_item/paragraph/task as appropriate"""

# --- Step 3: Tasks -------------------------------------------------------------

PROJECT_UPDATE_TASKS_PROMPT = """You update project TASKS from a daily log.

## Context

You receive which parts the log concerns, any **new parts** from step 1, a short summary, and proposed EXECUTION changes.

## Files (part-grouped)

Sections are marked `--- PART: Name ---`. Keep task edits inside the correct part.

INPUT — Daily log (read only).

TASKS — Calendar-sized missions under part headers. Simpler phrasing than execution.

## Rules

- Tasks are for organizing work the user can schedule — not a dump of every bullet.
- Group related small points into one task when they belong together.
- Align with execution intent but phrase more simply and actionably.
- If step 1 added new parts, add matching part headers in TASKS (`add_after` with `kind: "header"`) before adding tasks under them.

## Your job (step 3 of 4)

Return edits to TASKS only.

## Output

JSON only:
{"tasks_ops":[]}

Each op:
- op: "replace" | "remove" | "add_after"
- unit_id: from TASKS input (e.g. task:12) or list item id
- text: full new task title / line
- kind: use `"header"` when adding a new part section"""

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


def _format_parts_context(flattened: dict) -> str:
    plan_parts = flattened.get("plan_parts") or []
    if not plan_parts:
        return "Existing plan parts: (none)"
    quoted = ", ".join(f'"{name}"' for name in plan_parts)
    return f"Existing plan parts ({len(plan_parts)}): {quoted}"


def _run_plan_step(topic_name: str, flattened: dict, locale: str) -> dict:
    user_prompt = (
        f"Topic: {topic_name}\n"
        f"{_format_parts_context(flattened)}\n\n"
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
    new_parts = plan_result.get("new_parts") or []
    new_parts_line = (
        f"New parts to add in EXECUTION: {', '.join(new_parts)}\n"
        if new_parts
        else ""
    )
    user_prompt = (
        f"Topic: {topic_name}\n"
        f"{_format_parts_context(flattened)}\n"
        f"Parts touched: {', '.join(parts_touched) or primary or 'General'}\n"
        f"Primary part: {primary or 'General'}\n"
        f"{new_parts_line}"
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
    new_parts = plan_result.get("new_parts") or []
    new_parts_line = (
        f"New parts to add in TASKS: {', '.join(new_parts)}\n"
        if new_parts
        else ""
    )
    execution_ops = execution_result.get("execution_ops") or []
    user_prompt = (
        f"Topic: {topic_name}\n"
        f"{_format_parts_context(flattened)}\n"
        f"Parts touched: {', '.join(parts_touched) or primary or 'General'}\n"
        f"Primary part: {primary or 'General'}\n"
        f"{new_parts_line}"
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
    plan_units = annotate_units_with_parts(units_from_file(plan_file.id))
    execution_units = annotate_units_with_parts(units_from_file(execution_file.id))
    tasks_units = annotate_units_with_parts(units_from_file(tasks_file.id))
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
        "existing_parts": plan_result.get("existing_parts") or [],
        "new_parts": plan_result.get("new_parts") or [],
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
