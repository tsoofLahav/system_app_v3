"""Project update AI — header map, per-part flows (create / update / remove), doc."""

from __future__ import annotations

from datetime import date

from config import OPENAI_PROCESS_UPDATE_TEMPERATURE, OPENAI_PROJECT_UPDATE_TEMPERATURE
from models import AiProposal, db
from services.diff_engine import build_change_set, build_document_change_set
from services.openai_service import chat_json
from services.part_diff import build_create_part_ops
from services.part_edit_ops import EDIT_OPS_RULES, sanitize_part_edit_ops, summarize_ops
from services.unit_mapper import (
    annotate_units_with_parts,
    attach_mapped_log_content,
    build_part_removal_ops,
    detect_language,
    extract_log_sections,
    flatten_doc_recent_rows_for_ai,
    flatten_log_content,
    flatten_log_sections_for_mapping,
    flatten_part_units_with_ids,
    format_numbered_plan_headers,
    last_unit_id,
    list_log_sections_for_map,
    list_plan_headers,
    normalize_content_payload,
    parse_header_map_instructions,
    part_change_id_prefix,
    slice_units_by_part,
    summarize_parts_for_mapping,
    units_from_file,
)

# Part-level flows (after header map)
PART_ACTION_CREATE = "create"
PART_ACTION_UPDATE = "update"
PART_ACTION_REMOVE = "remove"

# Line-level ops inside an update flow (same contract as process update)
LINE_OP_REPLACE = "replace"   # edit existing line
LINE_OP_ADD = "add_after"     # new line
LINE_OP_REMOVE = "remove"     # drop line

PROJECT_UPDATE_HEADER_MAP_PROMPT = """You map a daily log to numbered project plan parts.

## Input
- PLAN_HEADERS — numbered canonical plan parts: [1] Name, [2] Name, …
- LOG_SECTIONS — indexed log section headers only: [0] Header, [1] Header, …

## Rules
Return ONLY parts that need action. Omit plan indices with nothing to do.

Each instruction uses exactly one action:
- remove — retire a plan part. Requires plan_index only.
- update — apply a log section to an existing plan part. Requires plan_index + log_section_index. Use when the log section belongs to that plan part, even if the header wording differs.
- create — add a new plan part from a log section. Requires log_section_index + part_name (verbatim log header text).

Never invent part names from log body text. Use log header text only for create part_name.

## Output
JSON only:
{
  "instructions": [
    {"action": "remove", "plan_index": 1},
    {"action": "update", "plan_index": 3, "log_section_index": 1},
    {"action": "create", "log_section_index": 0, "part_name": "A"}
  ],
  "log_date": "YYYY-MM-DD or empty"
}"""

PROJECT_UPDATE_PART_CREATE_PROMPT = """You write initial content for a new project part.

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

PROJECT_UPDATE_PART_EDIT_PROMPT = f"""You update one existing project part using today's log section.

This flow matches process update: return unit-level edit ops directly — not full rewritten arrays.

## File roles (this part only)
- PLAN — concise essence. Short list items.
- EXECUTION — durable work points. No dates, no diary tone.
- TASKS — calendar-sized missions. Actionable and simple.

## Input
- LOG CONTENT — today's notes for this part
- PLAN / EXECUTION / TASKS — current lines with unit_id prefixes like [block:1:item:0]

## Job
1. Read the log section and the current lines for this part in each file.
2. Return only the edits needed in that part.

{EDIT_OPS_RULES}

## Output
JSON only:
{{"plan_ops":[],"execution_ops":[],"tasks_ops":[]}}"""

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


def _run_header_map_step(topic_name, plan_units, log_sections, locale):
    user_prompt = (
        f"Topic: {topic_name}\n\n"
        f"=== PLAN_HEADERS ===\n"
        f"{format_numbered_plan_headers(plan_units)}\n\n"
        f"=== LOG_SECTIONS ===\n"
        f"{list_log_sections_for_map(log_sections)}"
    )
    raw = chat_json(
        f"{PROJECT_UPDATE_HEADER_MAP_PROMPT}\n\n{_lang_note(locale)}",
        user_prompt,
        temperature=OPENAI_PROJECT_UPDATE_TEMPERATURE,
    )
    return parse_header_map_instructions(raw, plan_units, log_sections)


def _run_part_create_flow(topic_name, part_entry, plan_units, execution_units, tasks_units, locale):
    """CREATE flow — AI writes content arrays; code builds add_after ops."""
    user_prompt = (
        f"Topic: {topic_name}\n"
        f"Part: {part_entry.get('part_name')}\n"
        f"Log header: {part_entry.get('log_header')}\n\n"
        f"=== LOG CONTENT ===\n"
        f"{part_entry.get('log_content') or '(empty)'}"
    )
    result = chat_json(
        f"{PROJECT_UPDATE_PART_CREATE_PROMPT}\n\n{_lang_note(locale)}",
        user_prompt,
        temperature=OPENAI_PROJECT_UPDATE_TEMPERATURE,
    )
    content = normalize_content_payload(result.get("content"))
    part_name = part_entry.get("part_name") or ""
    plan_ops = build_create_part_ops(plan_units, part_name, content.get("plan"), "plan")
    execution_ops = build_create_part_ops(
        execution_units, part_name, content.get("execution"), "execution"
    )
    tasks_ops = build_create_part_ops(
        tasks_units, part_name, content.get("tasks"), "tasks"
    )
    return {
        "content": content,
        "plan_ops": plan_ops,
        "execution_ops": execution_ops,
        "tasks_ops": tasks_ops,
        "op_summary": {
            "plan": summarize_ops(plan_ops),
            "execution": summarize_ops(execution_ops),
            "tasks": summarize_ops(tasks_ops),
        },
    }


def _run_part_update_flow(
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
    """UPDATE flow — like process update: one AI call returns unit-level ops per file."""
    part_name = part_entry.get("part_name") or ""
    user_prompt = (
        f"Topic: {topic_name}\n"
        f"Part: {part_name}\n"
        f"Log header: {part_entry.get('log_header')}\n\n"
        f"=== LOG CONTENT ===\n"
        f"{part_entry.get('log_content') or '(empty)'}\n\n"
        f"=== {plan_name.upper()} — PART: {part_name} ===\n"
        f"{flatten_part_units_with_ids(plan_units, part_name)}\n\n"
        f"=== {execution_name.upper()} — PART: {part_name} ===\n"
        f"{flatten_part_units_with_ids(execution_units, part_name)}\n\n"
        f"=== {tasks_name.upper()} — PART: {part_name} ===\n"
        f"{flatten_part_units_with_ids(tasks_units, part_name)}"
    )
    result = chat_json(
        f"{PROJECT_UPDATE_PART_EDIT_PROMPT}\n\n{_lang_note(locale)}",
        user_prompt,
        temperature=OPENAI_PROCESS_UPDATE_TEMPERATURE,
    )
    plan_ops = sanitize_part_edit_ops(result.get("plan_ops"), plan_units, part_name)
    execution_ops = sanitize_part_edit_ops(
        result.get("execution_ops"), execution_units, part_name
    )
    tasks_ops = sanitize_part_edit_ops(result.get("tasks_ops"), tasks_units, part_name)
    return {
        "content": {},
        "plan_ops": plan_ops,
        "execution_ops": execution_ops,
        "tasks_ops": tasks_ops,
        "op_summary": {
            "plan": summarize_ops(plan_ops),
            "execution": summarize_ops(execution_ops),
            "tasks": summarize_ops(tasks_ops),
        },
    }


def _run_part_remove_flow(plan_units, execution_units, tasks_units, part_name):
    """REMOVE flow — no AI; programmatic removal ops."""
    plan_ops = build_part_removal_ops(plan_units, part_name)
    execution_ops = build_part_removal_ops(execution_units, part_name)
    tasks_ops = build_part_removal_ops(tasks_units, part_name)
    return {
        "content": {},
        "plan_ops": plan_ops,
        "execution_ops": execution_ops,
        "tasks_ops": tasks_ops,
        "op_summary": {
            "plan": summarize_ops(plan_ops),
            "execution": summarize_ops(execution_ops),
            "tasks": summarize_ops(tasks_ops),
        },
    }


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


def _anchor_unit_for_create(full_units, part_name):
    anchor_id = last_unit_id(full_units)
    if not anchor_id:
        return None
    for unit in full_units:
        if unit.get("id") == anchor_id:
            return dict(unit)
    return {"id": anchor_id, "kind": "list_item", "text": ""}


def _display_units_for_part(action, part_name, key, units, annotated, ops, content_items):
    slice_units = slice_units_by_part(annotated, part_name)
    if action == "create":
        anchor = _anchor_unit_for_create(units, part_name)
        if anchor:
            anchor = dict(anchor)
            anchor["text"] = ""
            return [anchor]
        return []
    if action == "remove":
        return [unit for unit in slice_units if unit.get("kind") != "header"]
    if slice_units:
        return [unit for unit in slice_units if unit.get("kind") != "header"]
    return slice_units


def _build_part_file_document(
    action,
    part_name,
    key,
    title,
    full_units,
    annotated_units,
    ops,
    content_items,
):
    """Build change + review slices from the same ops (single source of truth)."""
    if not ops:
        return None
    id_prefix = part_change_id_prefix(key, part_name)
    change_doc = build_document_change_set(
        key, title, full_units, ops, id_prefix=id_prefix
    )
    display_units = _display_units_for_part(
        action, part_name, key, full_units, annotated_units, ops, content_items
    )
    return {
        "finalize": change_doc,
        "review": {
            "key": key,
            "title": title,
            "units": _units_with_part(display_units, part_name),
            "changes": change_doc["changes"],
            "review_bundle": action == PART_ACTION_REMOVE,
        },
    }


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
        content = result.get("content") or {}
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

        for key, title, units, annotated, ops, content_key in (
            ("plan", plan_name, plan_units, annotated_plan, plan_ops, "plan"),
            ("execution", execution_name, execution_units, annotated_execution, execution_ops, "execution"),
            ("tasks", tasks_name, tasks_units, annotated_tasks, tasks_ops, "tasks"),
        ):
            built = _build_part_file_document(
                action,
                part_name,
                key,
                title,
                units,
                annotated,
                ops,
                content.get(content_key),
            )
            if built:
                entry[key] = built["review"]
        if any(entry.get(k) for k in ("plan", "execution", "tasks")):
            review_parts.append(entry)
    return review_parts


def build_project_update_change_set(
    plan_file,
    execution_file,
    tasks_file,
    per_part_results,
):
    plan_units = annotate_units_with_parts(units_from_file(plan_file.id))
    execution_units = annotate_units_with_parts(units_from_file(execution_file.id))
    tasks_units = annotate_units_with_parts(units_from_file(tasks_file.id))

    documents_by_key = {}
    for result in per_part_results or []:
        part_name = (result.get("part_name") or "").strip()
        if not part_name:
            continue
        action = (result.get("action") or PART_ACTION_UPDATE).strip()
        content = result.get("content") or {}
        for key, title, units, ops_field in (
            ("plan", plan_file.name, plan_units, "plan_ops"),
            ("execution", execution_file.name, execution_units, "execution_ops"),
            ("tasks", tasks_file.name, tasks_units, "tasks_ops"),
        ):
            ops = result.get(ops_field) or []
            built = _build_part_file_document(
                action,
                part_name,
                key,
                title,
                units,
                units,
                ops,
                content.get(key),
            )
            if not built:
                continue
            finalize_doc = built["finalize"]
            if key not in documents_by_key:
                documents_by_key[key] = {
                    "key": key,
                    "title": title,
                    "units": units,
                    "changes": [],
                }
            documents_by_key[key]["changes"].extend(finalize_doc["changes"])

    return build_change_set(list(documents_by_key.values()))


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
        action = (part_entry.get("action") or PART_ACTION_UPDATE).strip().lower()
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
            "op_summary": {},
        }

        if action == PART_ACTION_CREATE:
            flow = _run_part_create_flow(
                topic.name, part_entry, plan_units, execution_units, tasks_units, locale
            )
            plan_structure_changed = True
        elif action == PART_ACTION_UPDATE:
            flow = _run_part_update_flow(
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
        else:
            continue

        step_record["content"] = flow.get("content") or {}
        step_record["ops"] = {
            "plan": flow.get("plan_ops") or [],
            "execution": flow.get("execution_ops") or [],
            "tasks": flow.get("tasks_ops") or [],
        }
        step_record["op_summary"] = flow.get("op_summary") or {}
        ai_part_steps.append(step_record)

        result = {
            "part_name": part_name,
            "log_header": part_entry.get("log_header") or part_name,
            "action": action,
            "content": flow.get("content") or {},
            "plan_ops": flow.get("plan_ops") or [],
            "execution_ops": flow.get("execution_ops") or [],
            "tasks_ops": flow.get("tasks_ops") or [],
        }
        per_part_results.append(result)
        _merge_ops(plan_ops, result["plan_ops"])
        _merge_ops(execution_ops, result["execution_ops"])
        _merge_ops(tasks_ops, result["tasks_ops"])

    removals = []
    for part_name in header_map.get("parts_to_remove") or []:
        part_name = (part_name or "").strip()
        if not part_name:
            continue
        flow = _run_part_remove_flow(plan_units, execution_units, tasks_units, part_name)
        removals.append({"part": part_name})
        _merge_ops(plan_ops, flow.get("plan_ops") or [])
        _merge_ops(execution_ops, flow.get("execution_ops") or [])
        _merge_ops(tasks_ops, flow.get("tasks_ops") or [])
        plan_structure_changed = True
        per_part_results.append(
            {
                "part_name": part_name,
                "log_header": part_name,
                "action": PART_ACTION_REMOVE,
                "plan_ops": flow.get("plan_ops") or [],
                "execution_ops": flow.get("execution_ops") or [],
                "tasks_ops": flow.get("tasks_ops") or [],
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
        per_part_results,
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
