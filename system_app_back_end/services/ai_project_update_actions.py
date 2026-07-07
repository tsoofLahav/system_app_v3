"""Project update AI — part mapping then plan → execution → tasks → doc."""

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
    summarize_parts_for_mapping,
    units_from_doc_table,
    units_from_file,
)

# --- Step 0: Part mapping (classification only) --------------------------------

PROJECT_UPDATE_PART_MAPPING_PROMPT = """You classify a project daily log against existing PLAN parts.

## What is a part?

Project parts are inner headers in PLAN. Each part has a short essence (bullets/text) describing that area of the project. The same part names appear in execution and tasks.

## Input

You receive:
- EXISTING PARTS with essence summaries
- INPUT — the daily log (read only)
- PLAN — part-grouped file for reference (read only)

## Your job (step 0 — no edits)

Decide whether the log belongs to existing part(s), requires new part(s), or both.

Create a **new part** when:
- The log **explicitly** names or sections a new work area, OR
- The log **implicitly** describes a coherent area that does **not** overlap existing part names or essences (different goals, deliverables, or subsystem).

Do **not** force unrelated log content into an existing part to avoid creating a new one.

## Output

JSON only:
{
  "existing_parts_matched": ["Part A"],
  "new_parts": [],
  "primary_scope": "existing",
  "mapping_reason": "2-4 sentences explaining the fit",
  "new_part_signals": []
}

`primary_scope`: "existing" | "new" | "mixed"
`new_parts`: part names to **create** — not in existing PLAN parts.
`new_part_signals`: short bullets citing explicit/implicit signals (e.g. "mentions billing integration", "no overlap with API part essence")."""

# --- Step 1: Plan ---------------------------------------------------------------

PROJECT_UPDATE_PLAN_PROMPT = """You update the project PLAN from a daily log.

## Binding part mapping (from step 0)

You receive a PART MAPPING block. It is **binding**:
- If `new_parts` is non-empty → you **must** bootstrap those parts in PLAN. Do **not** put that content under unrelated existing parts.
- If `primary_scope` is "new" or "mixed" → set `plan_structure_changed` true and include all `new_parts`.
- If only existing parts matched → edit only those parts.

## Files (part-grouped)

`PART LIST` lists existing part names. Sections use `--- PART: Name ---`.

PLAN parts contain: header + concise essence (list items / short text). Not execution detail.

## Two modes

### A) Update existing part
- `replace` / `add_after` / `remove` only inside the matched part block.

### B) Bootstrap new part (when mapping lists new_parts)
Create a **full part block** like existing ones:
1. `add_after` on last unit of last existing part (or last file unit) with `kind: "header"` and part name
2. 2–4 essence lines via further `add_after` on the **same anchor** with `kind: "list_item"` or `"paragraph"`

Example existing part:
--- PART: API ---
[header] API
[list_item] Define REST contracts
[list_item] Auth model

Example new part bootstrap (ops):
- add_after anchor_id kind=header text="Billing"
- add_after anchor_id kind=list_item text="Payment provider integration"
- add_after anchor_id kind=list_item text="Invoice schema"

## Output

JSON only:
{
  "existing_parts": ["Part A"],
  "new_parts": [],
  "parts_touched": ["Part name"],
  "primary_part": "Part name",
  "input_summary": "1-3 sentences",
  "plan_structure_changed": false,
  "plan_ops": []
}

`plan_ops` entries:
- op: "replace" | "remove" | "add_after"
- unit_id: from PLAN
- text: full new line
- kind: required for add_after — `"header"` for new part title; `"list_item"` / `"paragraph"` for essence"""

# --- Step 2: Execution ----------------------------------------------------------

PROJECT_UPDATE_EXECUTION_PROMPT = """You update project EXECUTION from a daily log.

## Binding part mapping

Follow the PART MAPPING block. If `new_parts` is listed, bootstrap matching sections in EXECUTION — do not dump that content into unrelated existing parts.

## Files (part-grouped)

Sections use `--- PART: Name ---`. EXECUTION holds durable work points (no dates, no diary tone).

## For each new part in mapping

1. `add_after` on last unit of last existing part with `kind: "header"` and part name
2. Add 2+ durable points via `add_after` on same anchor (`list_item` / `paragraph`)

## For existing parts

Before adding, check for similar points — `replace` first to avoid duplicates.

## Output

JSON only: {"execution_ops":[]}

Each op: op, unit_id, text, kind (use `"header"` for new part sections)"""

# --- Step 3: Tasks --------------------------------------------------------------

PROJECT_UPDATE_TASKS_PROMPT = """You update project TASKS from a daily log.

## Binding part mapping

Follow the PART MAPPING block. If `new_parts` is listed, bootstrap matching sections in TASKS.

## Files (part-grouped)

TASKS = calendar-sized missions under part headers. Simpler than execution.

## For each new part

1. `add_after` with `kind: "header"` for the part name
2. Add 1–3 actionable tasks under it via further `add_after`

## Rules

- Group related points into one task when sensible.
- Align with execution intent.

## Output

JSON only: {"tasks_ops":[]}

Each op: op, unit_id, text, kind (use `"header"` for new part sections)"""

# --- Step 4: Documentation (append-only) ----------------------------------------

PROJECT_UPDATE_DOC_PROMPT = """You append documentation rows from a project daily log.

## Files

INPUT — Daily log (read only).

DOCUMENTATION — Existing table (read only). **Historical record — never modify existing rows.**

## Rules (strict)

- **Append only.** Each op adds a **new row**. Never replace, remove, or rewrite an existing row.
- A row for 3.6 documents what happened on 3.6 forever. A log from 7.6 adds a **new** 7.6 row — it does not change old dates.
- Extract dated highlights from this log only.
- Multiple new rows for the same date are allowed.
- Infer date from the log; otherwise use the default date in the user message.

## Output

JSON only: {"doc_ops":[]}

Each entry (append only):
- date: YYYY-MM-DD
- text: entry text (no date prefix)

Do **not** return unit_id, replace, remove, or any op that edits existing rows."""


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


def _format_mapping_context(mapping: dict) -> str:
    matched = mapping.get("existing_parts_matched") or []
    new_parts = mapping.get("new_parts") or []
    scope = mapping.get("primary_scope") or "existing"
    reason = (mapping.get("mapping_reason") or "").strip()
    signals = mapping.get("new_part_signals") or []
    signals_line = ""
    if signals:
        signals_line = "Signals: " + "; ".join(str(s) for s in signals) + "\n"
    return (
        "PART MAPPING (binding):\n"
        f"- Matched existing: {', '.join(matched) or '(none)'}\n"
        f"- New parts to create: {', '.join(new_parts) or '(none)'}\n"
        f"- Scope: {scope}\n"
        f"- Reason: {reason or '(see mapping)'}\n"
        f"{signals_line}"
    ).strip()


def _normalize_doc_ops(doc_ops: list) -> list:
    """Keep append-only doc ops: {date, text} only."""
    normalized = []
    for op in doc_ops or []:
        if not isinstance(op, dict):
            continue
        if (op.get("op") or "").strip().lower() in ("replace", "remove"):
            continue
        date_val = (op.get("date") or "").strip()
        text = (op.get("text") or "").strip()
        if date_val and text:
            normalized.append({"date": date_val, "text": text})
    return normalized


def _plan_has_new_part_ops(plan_result: dict, mapping: dict) -> bool:
    new_parts = mapping.get("new_parts") or []
    if not new_parts:
        return True
    result_new = plan_result.get("new_parts") or []
    if result_new:
        return True
    for op in plan_result.get("plan_ops") or []:
        if (op.get("op") or "").strip().lower() != "add_after":
            continue
        if (op.get("kind") or "").strip().lower() == "header":
            return True
    return False


def _run_part_mapping_step(
    topic_name: str, flattened: dict, plan_units: list, locale: str
) -> dict:
    essence = summarize_parts_for_mapping(plan_units)
    user_prompt = (
        f"Topic: {topic_name}\n"
        f"{_format_parts_context(flattened)}\n\n"
        f"=== EXISTING PARTS (essence) ===\n{essence}\n\n"
        f"{flattened['input']}\n\n"
        f"{flattened['plan']}"
    )
    return chat_json(
        f"{PROJECT_UPDATE_PART_MAPPING_PROMPT}\n\n{_lang_note(locale)}",
        user_prompt,
        temperature=OPENAI_PROCESS_UPDATE_TEMPERATURE,
    )


def _run_plan_step(
    topic_name: str, flattened: dict, mapping: dict, locale: str
) -> dict:
    user_prompt = (
        f"Topic: {topic_name}\n"
        f"{_format_mapping_context(mapping)}\n\n"
        f"{flattened['input']}\n\n"
        f"{flattened['plan']}"
    )
    return chat_json(
        f"{PROJECT_UPDATE_PLAN_PROMPT}\n\n{_lang_note(locale)}",
        user_prompt,
        temperature=OPENAI_PROCESS_UPDATE_TEMPERATURE,
    )


def _run_plan_step_with_correction(
    topic_name: str, flattened: dict, mapping: dict, locale: str
) -> dict:
    new_parts = ", ".join(mapping.get("new_parts") or []) or "(see mapping)"
    correction = (
        f"CORRECTION: Step 0 requires new part(s): {new_parts}. "
        "You must add them via plan_ops (header + essence lines). "
        "Do not place this content under unrelated existing parts."
    )
    user_prompt = (
        f"Topic: {topic_name}\n"
        f"{_format_mapping_context(mapping)}\n\n"
        f"{correction}\n\n"
        f"{flattened['input']}\n\n"
        f"{flattened['plan']}"
    )
    return chat_json(
        f"{PROJECT_UPDATE_PLAN_PROMPT}\n\n{_lang_note(locale)}",
        user_prompt,
        temperature=OPENAI_PROCESS_UPDATE_TEMPERATURE,
    )


def _run_execution_step(
    topic_name: str,
    flattened: dict,
    mapping: dict,
    plan_result: dict,
    locale: str,
) -> dict:
    summary = (plan_result.get("input_summary") or "").strip()
    new_parts = plan_result.get("new_parts") or mapping.get("new_parts") or []
    new_parts_line = (
        f"New parts from plan: {', '.join(new_parts)}\n" if new_parts else ""
    )
    user_prompt = (
        f"Topic: {topic_name}\n"
        f"{_format_mapping_context(mapping)}\n"
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
    mapping: dict,
    plan_result: dict,
    execution_result: dict,
    locale: str,
) -> dict:
    summary = (plan_result.get("input_summary") or "").strip()
    new_parts = plan_result.get("new_parts") or mapping.get("new_parts") or []
    new_parts_line = (
        f"New parts from plan: {', '.join(new_parts)}\n" if new_parts else ""
    )
    execution_ops = execution_result.get("execution_ops") or []
    user_prompt = (
        f"Topic: {topic_name}\n"
        f"{_format_mapping_context(mapping)}\n"
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
    result = chat_json(
        f"{PROJECT_UPDATE_DOC_PROMPT}\n\n{_lang_note(locale)}",
        user_prompt,
        temperature=OPENAI_PROCESS_UPDATE_TEMPERATURE,
    )
    result["doc_ops"] = _normalize_doc_ops(result.get("doc_ops") or [])
    return result


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
    doc_ops = _normalize_doc_ops(ai_result.get("doc_ops") or [])

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
    plan_units = units_from_file(plan_file.id)
    locale = detect_language(
        flattened["input"],
        flattened["plan"],
        flattened["execution"],
        flattened["tasks"],
        flattened["documentation"],
    )

    log_date_hint = date.today().isoformat()

    mapping_result = _run_part_mapping_step(
        topic.name, flattened, plan_units, locale
    )
    plan_result = _run_plan_step(topic.name, flattened, mapping_result, locale)
    if not _plan_has_new_part_ops(plan_result, mapping_result):
        plan_result = _run_plan_step_with_correction(
            topic.name, flattened, mapping_result, locale
        )

    execution_result = _run_execution_step(
        topic.name, flattened, mapping_result, plan_result, locale
    )
    tasks_result = _run_tasks_step(
        topic.name,
        flattened,
        mapping_result,
        plan_result,
        execution_result,
        locale,
    )
    doc_result = _run_doc_step(topic.name, flattened, log_date_hint, locale)

    ai_result = {
        "part_mapping": {
            "existing_parts_matched": mapping_result.get("existing_parts_matched")
            or [],
            "new_parts": mapping_result.get("new_parts") or [],
            "primary_scope": mapping_result.get("primary_scope"),
            "mapping_reason": mapping_result.get("mapping_reason"),
        },
        "existing_parts": plan_result.get("existing_parts") or [],
        "new_parts": plan_result.get("new_parts")
        or mapping_result.get("new_parts")
        or [],
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
            "part_mapping": mapping_result,
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
