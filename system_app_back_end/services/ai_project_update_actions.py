"""Project update AI v2 — header map, content, diff, doc."""

from __future__ import annotations

from datetime import date

from config import OPENAI_PROCESS_UPDATE_TEMPERATURE, OPENAI_PROJECT_UPDATE_TEMPERATURE
from models import AiProposal, db
from services.diff_engine import build_change_set, build_document_change_set
from services.openai_service import chat_json
from services.part_diff import build_create_part_ops, sanitize_diff_ops
from services.unit_mapper import (
    annotate_units_with_parts,
    attach_mapped_log_content,
    build_part_removal_ops,
    detect_language,
    extract_log_sections,
    flatten_doc_recent_rows_for_ai,
    flatten_log_content,
    flatten_log_sections_for_mapping,
    flatten_part_content_for_update,
    flatten_part_units_with_ids,
    list_log_sections_for_map,
    list_plan_headers,
    normalize_content_payload,
    resolve_plan_part_name,
    slice_units_by_part,
    summarize_parts_for_mapping,
    synthesize_create_part_units,
    units_from_file,
)

PROJECT_UPDATE_HEADER_MAP_PROMPT = """You map daily log section headers to project plan parts.

## Input
- PLAN_HEADERS — canonical existing part names (from plan file)
- LOG_SECTIONS — indexed header text only (no body)

## Rules
For each log section:
- Header matches an existing plan part (by meaning) → action: update, part_name = exact string from PLAN_HEADERS
- Header does not match any plan part → action: create, part_name = verbatim log header text
- Header explicitly retires/cancels an existing plan part → action: remove, part_name = exact plan header being retired

Never invent part names from log body text or comments. Use header text only.

## Output
JSON only:
{
  "parts": [
    {
      "part_name": "Exact Name",
      "action": "update",
      "log_section_index": 0,
      "log_header": "verbatim log header"
    }
  ],
  "parts_to_remove": [],
  "log_date": "YYYY-MM-DD"
}"""

PROJECT_UPDATE_CREATE_CONTENT_PROMPT = """You write initial content for a new project part.

## File roles
- PLAN — concise essence (what this part is about). Short list items.
- EXECUTION — durable work points. No dates, no diary tone.
- TASKS — calendar-sized missions. Actionable and simple.

## Input
One log section (header + today's notes for this area).

## Job
Write initial plan, execution, and tasks content for this new part from the log.

## Output
JSON only:
{
  "content": {
    "plan": ["..."],
    "execution": ["..."],
    "tasks": ["..."]
  }
}"""

PROJECT_UPDATE_UPDATE_CONTENT_PROMPT = """You revise existing part content using today's log section.

## File roles
- PLAN — concise essence. Short list items.
- EXECUTION — durable work points. No dates, no diary tone.
- TASKS — calendar-sized missions. Actionable and simple.

## Input
- Log section (today's notes)
- Current plan, execution, and tasks content for this part (text only, no IDs)

## Job
Return full updated content arrays that integrate the log. Prefer updating similar lines over duplicating.

## Output
JSON only:
{
  "content": {
    "plan": ["..."],
    "execution": ["..."],
    "tasks": ["..."]
  }
}"""

PROJECT_UPDATE_DIFF_PROMPT = """You suggest minimal edit ops to transform OLD content into NEW content.

## Input
- OLD — lines with unit_id prefixes like [block:1:item:0] text
- NEW — target text lines (array)

## Job
Return ops on OLD only: replace, add_after, remove.
- replace — change an existing line
- add_after — insert after a unit_id (include kind: list_item or task)
- remove — delete a unit

Keep ops minimal. Do not duplicate lines already matching NEW.

## Output
JSON only: {"ops":[]}"""

PROJECT_UPDATE_DOC_PROMPT = """You append documentation rows from a project daily log.

## Rules
- Append only. Never modify existing rows.
- Write what happened this day: progress, decisions, blockers, new/removed parts.
- One focused highlight per row. 1+ rows when the log has distinct events.
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


def _normalize_header_map_result(result, plan_units, log_sections):
    plan_headers = list_plan_headers(plan_units)
    normalized_parts = []

    for entry in result.get("parts") or result.get("sections") or []:
        if not isinstance(entry, dict):
            continue
        action = (entry.get("action") or "update").strip().lower()
        part_name = (
            entry.get("part_name")
            or entry.get("target_part")
            or entry.get("log_header")
            or ""
        ).strip()
        log_header = (entry.get("log_header") or "").strip()

        part_entry = {
            "part_name": part_name,
            "action": action,
            "log_section_index": entry.get("log_section_index"),
            "log_header": log_header,
        }
        attach_mapped_log_content(part_entry, log_sections)

        if action == "create" and part_entry.get("log_header"):
            part_entry["part_name"] = part_entry["log_header"]
        elif action == "update":
            part_entry["part_name"] = resolve_plan_part_name(
                plan_units, part_entry.get("part_name") or part_entry.get("log_header")
            )
        elif action == "remove":
            part_entry["part_name"] = resolve_plan_part_name(
                plan_units, part_entry.get("part_name") or part_entry.get("log_header")
            )

        if action in ("update", "create") and part_entry.get("log_content") is None:
            continue
        if action in ("update", "create", "remove") and part_entry.get("part_name"):
            normalized_parts.append(part_entry)

    parts_to_remove = []
    for name in result.get("parts_to_remove") or []:
        resolved = resolve_plan_part_name(plan_units, name)
        if resolved and resolved not in parts_to_remove:
            parts_to_remove.append(resolved)

    for entry in normalized_parts:
        if entry.get("action") == "remove":
            name = entry.get("part_name")
            if name and name not in parts_to_remove:
                parts_to_remove.append(name)

    content_parts = [
        entry
        for entry in normalized_parts
        if entry.get("action") in ("update", "create")
    ]

    return {
        "parts": content_parts,
        "parts_to_remove": parts_to_remove,
        "log_date": (result.get("log_date") or "").strip(),
    }


def _run_header_map_step(topic_name, plan_units, log_sections, locale):
    user_prompt = (
        f"Topic: {topic_name}\n\n"
        f"=== PLAN_HEADERS ===\n"
        f"{chr(10).join(f'- {name}' for name in list_plan_headers(plan_units)) or '(none)'}\n\n"
        f"=== LOG_SECTIONS ===\n"
        f"{list_log_sections_for_map(log_sections)}"
    )
    raw = chat_json(
        f"{PROJECT_UPDATE_HEADER_MAP_PROMPT}\n\n{_lang_note(locale)}",
        user_prompt,
        temperature=OPENAI_PROJECT_UPDATE_TEMPERATURE,
    )
    return _normalize_header_map_result(raw, plan_units, log_sections)


def _run_create_content_step(topic_name, part_entry, locale):
    user_prompt = (
        f"Topic: {topic_name}\n"
        f"Part: {part_entry.get('part_name')}\n"
        f"Log header: {part_entry.get('log_header')}\n\n"
        f"=== LOG CONTENT ===\n"
        f"{part_entry.get('log_content') or '(empty)'}"
    )
    result = chat_json(
        f"{PROJECT_UPDATE_CREATE_CONTENT_PROMPT}\n\n{_lang_note(locale)}",
        user_prompt,
        temperature=OPENAI_PROJECT_UPDATE_TEMPERATURE,
    )
    return normalize_content_payload(result.get("content"))


def _run_update_content_step(
    topic_name,
    part_entry,
    plan_units,
    execution_units,
    tasks_units,
    plan_name,
    execution_name,
    tasks_name,
    locale,
):
    part_name = part_entry.get("part_name") or ""
    user_prompt = (
        f"Topic: {topic_name}\n"
        f"Part: {part_name}\n"
        f"Log header: {part_entry.get('log_header')}\n\n"
        f"=== LOG CONTENT ===\n"
        f"{part_entry.get('log_content') or '(empty)'}\n\n"
        f"{flatten_part_content_for_update(plan_units, plan_name, part_name)}\n\n"
        f"{flatten_part_content_for_update(execution_units, execution_name, part_name)}\n\n"
        f"{flatten_part_content_for_update(tasks_units, tasks_name, part_name)}"
    )
    result = chat_json(
        f"{PROJECT_UPDATE_UPDATE_CONTENT_PROMPT}\n\n{_lang_note(locale)}",
        user_prompt,
        temperature=OPENAI_PROJECT_UPDATE_TEMPERATURE,
    )
    return normalize_content_payload(result.get("content"))


def _run_diff_step(
    file_key,
    file_title,
    part_name,
    units,
    new_items,
    locale,
):
    old_text = flatten_part_units_with_ids(units, part_name)
    new_lines = "\n".join(f"- {item}" for item in new_items) or "(empty)"
    user_prompt = (
        f"File: {file_title}\n"
        f"Part: {part_name}\n\n"
        f"=== OLD ===\n{old_text}\n\n"
        f"=== NEW ===\n{new_lines}"
    )
    result = chat_json(
        f"{PROJECT_UPDATE_DIFF_PROMPT}\n\n{_lang_note(locale)}",
        user_prompt,
        temperature=OPENAI_PROJECT_UPDATE_TEMPERATURE,
    )
    return sanitize_diff_ops(
        result.get("ops") or [],
        units,
        part_name,
        new_items,
        file_key,
    )


def _run_doc_step(topic_name, log_sections, doc_file, log_date_hint, locale):
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


def _units_with_part(doc_units, part_name):
    rows = []
    for unit in doc_units:
        row = dict(unit)
        row.setdefault("part", part_name)
        rows.append(row)
    return rows


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
        part_name = (result.get("part_name") or "").strip()
        if not part_name:
            continue
        action = (result.get("action") or "update").strip()
        plan_ops = result.get("plan_ops") or []
        execution_ops = result.get("execution_ops") or []
        tasks_ops = result.get("tasks_ops") or []
        if not plan_ops and not execution_ops and not tasks_ops:
            continue

        entry = {
            "part_name": part_name,
            "log_header": result.get("log_header") or part_name,
            "action": action,
        }
        annotated_plan = annotate_units_with_parts(plan_units)
        annotated_execution = annotate_units_with_parts(execution_units)
        annotated_tasks = annotate_units_with_parts(tasks_units)

        for key, title, units, annotated, ops in (
            ("plan", plan_name, plan_units, annotated_plan, plan_ops),
            ("execution", execution_name, execution_units, annotated_execution, execution_ops),
            ("tasks", tasks_name, tasks_units, annotated_tasks, tasks_ops),
        ):
            if not ops:
                continue
            slice_units = slice_units_by_part(annotated, part_name)
            if slice_units:
                display_units = slice_units
            elif action == "create":
                display_units = synthesize_create_part_units(part_name, ops, key)
            else:
                display_units = slice_units

            doc = build_document_change_set(key, title, display_units, ops)
            entry[key] = {
                "key": key,
                "title": title,
                "units": _units_with_part(doc["units"], part_name),
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
    units = units_from_file(input_file.id)
    return bool(list_plan_headers(units))


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

    header_map = _run_header_map_step(topic.name, plan_units, log_sections, locale)
    if header_map.get("log_date"):
        log_date_hint = header_map["log_date"]

    plan_ops: list = []
    execution_ops: list = []
    tasks_ops: list = []
    plan_structure_changed = False
    per_part_results = []
    ai_part_steps = []

    for part_entry in header_map.get("parts") or []:
        action = (part_entry.get("action") or "update").strip().lower()
        part_name = (part_entry.get("part_name") or "").strip()
        if not part_name:
            continue

        step_record = {
            "part_name": part_name,
            "action": action,
            "log_header": part_entry.get("log_header"),
            "log_section_index": part_entry.get("log_section_index"),
            "log_content": part_entry.get("log_content"),
            "content": {},
            "ops": {"plan": [], "execution": [], "tasks": []},
        }

        if action == "create":
            content = _run_create_content_step(topic.name, part_entry, locale)
            step_record["content"] = content
            part_plan_ops = build_create_part_ops(
                plan_units, part_name, content.get("plan"), "plan"
            )
            part_execution_ops = build_create_part_ops(
                execution_units, part_name, content.get("execution"), "execution"
            )
            part_tasks_ops = build_create_part_ops(
                tasks_units, part_name, content.get("tasks"), "tasks"
            )
            plan_structure_changed = True
        elif action == "update":
            content = _run_update_content_step(
                topic.name,
                part_entry,
                plan_units,
                execution_units,
                tasks_units,
                plan_file.name,
                execution_file.name,
                tasks_file.name,
                locale,
            )
            step_record["content"] = content
            part_plan_ops = _run_diff_step(
                "plan", plan_file.name, part_name, plan_units, content.get("plan"), locale
            )
            part_execution_ops = _run_diff_step(
                "execution",
                execution_file.name,
                part_name,
                execution_units,
                content.get("execution"),
                locale,
            )
            part_tasks_ops = _run_diff_step(
                "tasks", tasks_file.name, part_name, tasks_units, content.get("tasks"), locale
            )
        else:
            continue

        step_record["ops"] = {
            "plan": part_plan_ops,
            "execution": part_execution_ops,
            "tasks": part_tasks_ops,
        }
        ai_part_steps.append(step_record)

        result = {
            "part_name": part_name,
            "log_header": part_entry.get("log_header") or part_name,
            "action": action,
            "content": content,
            "plan_ops": part_plan_ops,
            "execution_ops": part_execution_ops,
            "tasks_ops": part_tasks_ops,
        }
        per_part_results.append(result)
        _merge_ops(plan_ops, part_plan_ops)
        _merge_ops(execution_ops, part_execution_ops)
        _merge_ops(tasks_ops, part_tasks_ops)

    removals = []
    for part_name in header_map.get("parts_to_remove") or []:
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
        per_part_results.append(
            {
                "part_name": part_name,
                "log_header": part_name,
                "action": "remove",
                "plan_ops": build_part_removal_ops(plan_units, part_name),
                "execution_ops": build_part_removal_ops(execution_units, part_name),
                "tasks_ops": build_part_removal_ops(tasks_units, part_name),
            }
        )

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
            "header_map": header_map,
            "parts": ai_part_steps,
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
