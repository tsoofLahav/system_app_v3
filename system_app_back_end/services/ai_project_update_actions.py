"""Project update AI — header-driven log sections, per-part updates, auto doc."""

from __future__ import annotations

from datetime import date

from config import OPENAI_PROCESS_UPDATE_TEMPERATURE
from models import AiProposal, db
from services.diff_engine import build_change_set, build_document_change_set
from services.openai_service import chat_json
from services.unit_mapper import (
    annotate_units_with_parts,
    build_part_removal_ops,
    detect_language,
    extract_log_sections,
    flatten_doc_recent_rows_for_ai,
    flatten_log_section,
    flatten_log_sections_for_mapping,
    flatten_single_part_for_ai,
    last_unit_id,
    slice_units_by_part,
    summarize_parts_for_mapping,
    units_from_file,
)

PROJECT_UPDATE_SECTION_MAPPING_PROMPT = """You map sections of a daily log to project parts.

## Input

- EXISTING PARTS — names and short essence summaries (read only)
- LOG SECTIONS — each section has a header (as the user wrote it) and a short excerpt

The log header text may **not** exactly match existing part names. Match by **meaning**.

## Your job (classification only — no file edits)

For each log section, decide:
- `action: "update"` — maps to an existing part (`target_part` = canonical existing name)
- `action: "create"` — describes a new project area (`target_part` = new canonical name)

Also list `parts_to_remove` only when the log **explicitly** states a part/mission should be removed.

Infer `log_date` (YYYY-MM-DD) from the log when possible.

## Output

JSON only:
{
  "sections": [
    {
      "log_header": "header text from log",
      "action": "update",
      "target_part": "Canonical Part Name",
      "mapping_note": "why this match"
    }
  ],
  "parts_to_remove": [],
  "log_date": "YYYY-MM-DD"
}"""

PROJECT_UPDATE_PER_PART_PROMPT = """You update a **single project part** in PLAN, EXECUTION, and TASKS.

You are updating one part only. Ignore anything outside this part. Do not reference other parts.

## Scope

You receive:
- The mapping for this part (log header → target part, update or create)
- **One log section** only — what the user wrote for this part today
- **Single-part slices** of PLAN, EXECUTION, and TASKS — only this part's content (or "part does not exist yet")

## Three files (same part)

**PLAN** — part header + concise essence (list items / short text). Not execution detail.

**EXECUTION** — durable work points under the part header. No dates, no diary tone.

**TASKS** — calendar-sized missions. Simpler and more actionable than execution.

## Rules

### action: update
- Edit only units in the provided part slices.
- Replace similar existing points before adding duplicates.

### action: create
- Part does not exist yet. Bootstrap a full part block in each file:
  1. `add_after` on the given anchor `unit_id` with `kind: "header"` and `text` = target part name
  2. Further `add_after` on the **same anchor** for essence (plan), points (execution), tasks (tasks)
- Set `plan_structure_changed` true.

## Output

JSON only:
{
  "target_part": "Part name",
  "action": "update",
  "plan_structure_changed": false,
  "plan_ops": [],
  "execution_ops": [],
  "tasks_ops": []
}

Each op: op (`replace` | `remove` | `add_after`), unit_id, text, kind (`header` | `list_item` | `paragraph` | `task` as needed)"""

PROJECT_UPDATE_DOC_PROMPT = """You append documentation rows from a project daily log.

## Input

- LOG — section-grouped daily log (read only)
- RECENT DOCUMENTATION — last few rows for tone reference only

## Rules

- **Append only.** Never modify existing rows.
- Write what happened **this day**: progress per part, discussions, decisions, plan changes, new/removed parts, blockers.
- Not execution-level bullet dumps. One focused highlight per row.
- 1+ rows depending on log richness — add more rows only when the log has distinct events worth separate lines.
- Use the provided default date when the log does not state one.

## Output

JSON only: {"doc_ops":[]}

Each entry: date (YYYY-MM-DD), text (no date prefix in text)"""


def _lang_note(locale: str) -> str:
    return "Respond in Hebrew." if locale == "he" else "Respond in English."


def _normalize_doc_ops(doc_ops: list) -> list:
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


def _find_log_section(log_sections, log_header: str) -> dict | None:
    key = (log_header or "").strip().lower()
    for section in log_sections:
        header = (section.get("header") or "").strip().lower()
        if header == key:
            return section
    return None


def _run_section_mapping_step(
    topic_name: str,
    plan_units: list,
    log_sections: list,
    locale: str,
) -> dict:
    essence = summarize_parts_for_mapping(plan_units)
    sections_text = flatten_log_sections_for_mapping(log_sections)
    user_prompt = (
        f"Topic: {topic_name}\n\n"
        f"=== EXISTING PARTS (essence) ===\n{essence}\n\n"
        f"=== LOG SECTIONS ===\n{sections_text}"
    )
    return chat_json(
        f"{PROJECT_UPDATE_SECTION_MAPPING_PROMPT}\n\n{_lang_note(locale)}",
        user_prompt,
        temperature=OPENAI_PROCESS_UPDATE_TEMPERATURE,
    )


def _run_per_part_step(
    topic_name: str,
    section_entry: dict,
    log_section: dict,
    plan_units: list,
    execution_units: list,
    tasks_units: list,
    plan_name: str,
    execution_name: str,
    tasks_name: str,
    locale: str,
) -> dict:
    target_part = (section_entry.get("target_part") or "").strip()
    action = (section_entry.get("action") or "update").strip()
    log_header = (section_entry.get("log_header") or "").strip()
    mapping_note = (section_entry.get("mapping_note") or "").strip()

    plan_anchor = last_unit_id(plan_units)
    execution_anchor = last_unit_id(execution_units)
    tasks_anchor = last_unit_id(tasks_units)

    user_prompt = (
        f"Topic: {topic_name}\n"
        f"Target part: {target_part}\n"
        f"Action: {action}\n"
        f"Log header: {log_header}\n"
        f"Mapping note: {mapping_note or '(none)'}\n\n"
        f"{flatten_log_section(log_section)}\n\n"
        f"{flatten_single_part_for_ai(plan_units, plan_name, target_part)}\n\n"
        f"{flatten_single_part_for_ai(execution_units, execution_name, target_part)}\n\n"
        f"{flatten_single_part_for_ai(tasks_units, tasks_name, target_part)}\n\n"
        f"Anchors for create add_after: plan={plan_anchor}, "
        f"execution={execution_anchor}, tasks={tasks_anchor}"
    )
    result = chat_json(
        f"{PROJECT_UPDATE_PER_PART_PROMPT}\n\n{_lang_note(locale)}",
        user_prompt,
        temperature=OPENAI_PROCESS_UPDATE_TEMPERATURE,
    )
    result.setdefault("target_part", target_part)
    result.setdefault("action", action)
    return result


def _run_doc_step(
    topic_name: str,
    log_sections: list,
    doc_file,
    log_date_hint: str,
    locale: str,
) -> dict:
    log_text = flatten_log_sections_for_mapping(
        log_sections, max_excerpt_lines=20
    ).replace("SECTION:", "LOG SECTION:")
    recent_doc = flatten_doc_recent_rows_for_ai(doc_file)
    user_prompt = (
        f"Topic: {topic_name}\n"
        f"Default date if not in log: {log_date_hint}\n\n"
        f"=== LOG ===\n{log_text}\n\n"
        f"{recent_doc}"
    )
    result = chat_json(
        f"{PROJECT_UPDATE_DOC_PROMPT}\n\n{_lang_note(locale)}",
        user_prompt,
        temperature=OPENAI_PROCESS_UPDATE_TEMPERATURE,
    )
    result["doc_ops"] = _normalize_doc_ops(result.get("doc_ops") or [])
    return result


def _merge_ops(target: list, source: list) -> None:
    if source:
        target.extend(source)


def build_review_parts(
    per_part_results,
    plan_units,
    execution_units,
    tasks_units,
    plan_name,
    execution_name,
    tasks_name,
):
    review_parts = []
    for result in per_part_results:
        part_name = (result.get("target_part") or "").strip()
        if not part_name:
            continue
        plan_ops = result.get("plan_ops") or []
        execution_ops = result.get("execution_ops") or []
        tasks_ops = result.get("tasks_ops") or []
        if not plan_ops and not execution_ops and not tasks_ops:
            continue

        entry = {
            "part_name": part_name,
            "log_header": result.get("log_header") or part_name,
            "action": result.get("action") or "update",
        }
        for key, title, units, ops in (
            ("plan", plan_name, plan_units, plan_ops),
            ("execution", execution_name, execution_units, execution_ops),
            ("tasks", tasks_name, tasks_units, tasks_ops),
        ):
            slice_units = slice_units_by_part(units, part_name)
            display_units = slice_units if slice_units else units
            if not ops:
                continue
            doc = build_document_change_set(key, title, display_units, ops)
            entry[key] = {
                "key": key,
                "title": title,
                "units": doc["units"],
                "changes": doc["changes"],
            }
        if any(entry.get(k) for k in ("plan", "execution", "tasks")):
            review_parts.append(entry)
    return review_parts


def build_project_update_change_set(
    plan_file,
    execution_file,
    tasks_file,
    ai_result,
):
    plan_units = annotate_units_with_parts(units_from_file(plan_file.id))
    execution_units = annotate_units_with_parts(units_from_file(execution_file.id))
    tasks_units = annotate_units_with_parts(units_from_file(tasks_file.id))

    documents = []
    plan_ops = ai_result.get("plan_ops") or []
    execution_ops = ai_result.get("execution_ops") or []
    tasks_ops = ai_result.get("tasks_ops") or []

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

    return build_change_set(documents)


def input_log_has_part_headers(input_file) -> bool:
    from services.unit_mapper import extract_part_names

    units = units_from_file(input_file.id)
    return bool(extract_part_names(units))


def smart_project_update(
    topic,
    input_file,
    plan_file,
    execution_file,
    tasks_file,
    doc_file,
):
    input_units = units_from_file(input_file.id)
    plan_units = units_from_file(plan_file.id)
    execution_units = units_from_file(execution_file.id)
    tasks_units = units_from_file(tasks_file.id)
    log_sections = extract_log_sections(input_units)

    locale = detect_language(
        flatten_log_sections_for_mapping(log_sections),
        summarize_parts_for_mapping(plan_units),
    )

    log_date_hint = date.today().isoformat()

    mapping_result = _run_section_mapping_step(
        topic.name, plan_units, log_sections, locale
    )

    plan_ops: list = []
    execution_ops: list = []
    tasks_ops: list = []
    plan_structure_changed = False
    per_part_results = []

    for section_entry in mapping_result.get("sections") or []:
        log_header = (section_entry.get("log_header") or "").strip()
        log_section = _find_log_section(log_sections, log_header)
        if log_section is None:
            continue

        result = _run_per_part_step(
            topic.name,
            section_entry,
            log_section,
            plan_units,
            execution_units,
            tasks_units,
            plan_file.name,
            execution_file.name,
            tasks_file.name,
            locale,
        )
        result["log_header"] = log_header
        per_part_results.append(result)
        _merge_ops(plan_ops, result.get("plan_ops") or [])
        _merge_ops(execution_ops, result.get("execution_ops") or [])
        _merge_ops(tasks_ops, result.get("tasks_ops") or [])
        if result.get("plan_structure_changed"):
            plan_structure_changed = True

    removals = []
    for part_name in mapping_result.get("parts_to_remove") or []:
        part_name = (part_name or "").strip()
        if not part_name:
            continue
        removals.append({"part": part_name})
        _merge_ops(plan_ops, build_part_removal_ops(plan_units, part_name))
        _merge_ops(
            execution_ops, build_part_removal_ops(execution_units, part_name)
        )
        _merge_ops(tasks_ops, build_part_removal_ops(tasks_units, part_name))
        plan_structure_changed = True

    doc_result = _run_doc_step(
        topic.name, log_sections, doc_file, log_date_hint, locale
    )
    doc_ops = doc_result.get("doc_ops") or []

    ai_result = {
        "plan_structure_changed": plan_structure_changed,
        "plan_ops": plan_ops,
        "execution_ops": execution_ops,
        "tasks_ops": tasks_ops,
        "doc_ops": doc_ops,
    }

    change_set = build_project_update_change_set(
        plan_file,
        execution_file,
        tasks_file,
        ai_result,
    )

    review_parts = build_review_parts(
        per_part_results,
        plan_units,
        execution_units,
        tasks_units,
        plan_file.name,
        execution_file.name,
        tasks_file.name,
    )

    return {
        "locale": locale,
        "plan_structure_changed": plan_structure_changed,
        "doc_ops": doc_ops,
        "review_parts": review_parts,
        "ai_steps": {
            "section_mapping": mapping_result,
            "per_part": per_part_results,
            "removals": removals,
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


def create_project_update_skipped_proposal(topic, missing_types, message, skip_reason=None):
    payload = {
        "missing_types": missing_types,
        "message": message,
    }
    if skip_reason:
        payload["skip_reason"] = skip_reason
    proposal = AiProposal(
        topic_id=topic.id,
        target_file_id=None,
        proposal_type="project_update_skipped",
        payload=payload,
        status="pending",
    )
    db.session.add(proposal)
    db.session.flush()
    return proposal
