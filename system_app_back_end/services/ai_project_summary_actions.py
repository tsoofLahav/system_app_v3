from __future__ import annotations

import json

from sqlalchemy import or_
from sqlalchemy.orm.attributes import flag_modified

from config import OPENAI_PROCESS_UPDATE_TEMPERATURE
from models import Block, File, Task, TaskView, Topic, db
from services.openai_service import chat_json
from services.task_view_flags import IMPORTANT_SECTION_FLAG
from services.unit_mapper import (
    detect_language,
    flatten_doc_file_for_ai,
    flatten_units_for_ai,
    units_from_file,
)

PROJECT_SUMMARY_UPDATE_PROMPT = """You update a project overview from project source files.

## Project parts
Project parts are ordered inner headers shared by plan, execution, and tasks.
Infer the ordered part list from all inputs for display in the overview only.
Do not propose edits to source files.

## Current part
Infer the current main part in progress from recent documentation, execution
details, flagged tasks, and wording in the source files.

## Overview output
Write a compact overview that surfaces the current state first. Return:
- summary_text: where the project is now, considering all parts.
- current_part_update: a focused update for the current part.
- recent_rows: the last project-in-progress dates, newest first, up to the
  requested limit. Each row should summarize what was done and what should
  happen next.

## Output
JSON only:
{
  "parts": [{"title": "Part name"}],
  "current_part": "Part name",
  "summary_text": "short project summary",
  "current_part_update": "focused current-part update",
  "recent_rows": [
    {"date": "17.6", "done": "what happened", "next": "what should happen next"}
  ]
}

Respond in the same language as the input files."""

GENERATED_BY = "project_summary_update"
CORE_PART_FILE_ROLES = ("plan", "execution", "tasks")


def smart_project_summary_update(
    topic: Topic,
    overview_file: File,
    plan_file: File,
    execution_file: File,
    tasks_file: File,
    doc_file: File | None = None,
    *,
    max_date_groups: int = 3,
):
    core_files = {
        "plan": plan_file,
        "execution": execution_file,
        "tasks": tasks_file,
    }
    existing_parts = _ordered_existing_parts(core_files.values())
    previous_overview = _overview_text(overview_file)
    plan_text = flatten_units_for_ai(units_from_file(plan_file.id), plan_file.name)
    execution_text = flatten_units_for_ai(
        units_from_file(execution_file.id),
        execution_file.name,
    )
    tasks_text = flatten_units_for_ai(units_from_file(tasks_file.id), tasks_file.name)
    doc_text = flatten_doc_file_for_ai(doc_file) if doc_file is not None else ""
    flagged = _flagged_tasks_for_topic(topic.id)
    flagged_lines = "\n".join(f"- {task.title}" for task in flagged if task.title)

    locale = detect_language(
        previous_overview,
        plan_text,
        execution_text,
        tasks_text,
        doc_text,
        flagged_lines,
        "\n".join(existing_parts),
    )
    if locale == "he":
        lang_note = (
            "All user-visible JSON string values must be written in Hebrew. "
            "Do not translate existing Hebrew part names into English."
        )
    else:
        lang_note = "All user-visible JSON string values must be written in English."

    user_prompt = (
        f"Project: {topic.name}\n"
        f"Max recent_rows: {max_date_groups}\n"
        f"Existing parts by first-seen order: {json.dumps(existing_parts, ensure_ascii=False)}\n\n"
        f"=== PREVIOUS OVERVIEW ===\n{previous_overview or '(empty)'}\n\n"
        f"{plan_text}\n\n"
        f"{execution_text}\n\n"
        f"{tasks_text}\n\n"
        f"{doc_text or _empty_documentation_text()}\n\n"
        f"=== FLAGGED TASKS (any view) ===\n{flagged_lines or '(none)'}"
    )

    ai_result = chat_json(
        f"{PROJECT_SUMMARY_UPDATE_PROMPT}\n\n{lang_note}",
        user_prompt,
        temperature=OPENAI_PROCESS_UPDATE_TEMPERATURE,
    )

    parts = _normalize_parts(ai_result.get("parts"), existing_parts)
    current_part = _match_part(ai_result.get("current_part"), parts) or (
        parts[0] if parts else ""
    )
    task_part_map = _task_part_map(tasks_file)
    current_tasks, other_tasks = _split_flagged_tasks(
        flagged,
        task_part_map,
        current_part,
    )

    summary_text = str(ai_result.get("summary_text") or "").strip()
    current_part_update = str(ai_result.get("current_part_update") or "").strip()
    recent_rows = _normalize_recent_rows(
        ai_result.get("recent_rows") or [],
        max_date_groups,
    )

    _apply_project_overview(
        overview_file,
        locale=locale,
        summary_text=summary_text,
        current_part=current_part,
        current_part_update=current_part_update,
        current_tasks=current_tasks,
        other_tasks=other_tasks,
        recent_rows=recent_rows,
        parts=parts,
    )

    return {
        "topic_id": topic.id,
        "overview_file_id": overview_file.id,
        "part_count": len(parts),
        "current_part": current_part,
        "current_flagged_task_count": len(current_tasks),
        "other_flagged_task_count": len(other_tasks),
        "recent_row_count": len(recent_rows),
    }


def _overview_text(overview_file: File) -> str:
    lines = []
    for block in _active_blocks(overview_file.id):
        text = _block_text(block)
        if text:
            lines.append(text)
    return "\n".join(lines)


def _ordered_existing_parts(files) -> list[str]:
    seen = set()
    parts = []
    for file in files:
        for section in _sections_for_file(file)["sections"]:
            key = _part_key(section["title"])
            if not key or key in seen:
                continue
            seen.add(key)
            parts.append(section["title"])
    return parts


def _normalize_parts(raw_parts, existing_parts: list[str]) -> list[str]:
    parts = []
    seen = set()

    def add(title):
        title = str(title or "").strip()
        key = _part_key(title)
        if not key or key in seen:
            return
        seen.add(key)
        parts.append(title)

    for item in raw_parts or []:
        if isinstance(item, dict):
            add(item.get("title") or item.get("name"))
        else:
            add(item)
    for title in existing_parts:
        add(title)
    if not parts:
        parts.append("General")
    return parts


def _match_part(value, parts: list[str]) -> str | None:
    key = _part_key(value)
    if not key:
        return None
    for part in parts:
        if _part_key(part) == key:
            return part
    return None


def _sections_for_file(file: File) -> dict:
    blocks = _active_blocks(file.id)
    preamble = []
    sections = []
    current = None
    for block in blocks:
        if block.type == "header" and _header_text(block):
            current = {
                "title": _header_text(block),
                "header": block,
                "blocks": [block],
            }
            sections.append(current)
            continue
        if current is None:
            preamble.append(block)
        else:
            current["blocks"].append(block)
    return {"preamble": preamble, "sections": sections}

def _part_header_content(title: str, is_current: bool = False) -> dict:
    content = {"text": title, "level": 2}
    if is_current:
        content["is_current_part"] = True
    return content


def _task_part_map(tasks_file: File) -> dict[int, str]:
    result = {}
    current_part = None
    for block in _active_blocks(tasks_file.id):
        if block.type == "header" and _header_text(block):
            current_part = _header_text(block)
            continue
        if block.type != "task":
            continue
        task_id = (block.content or {}).get("task_id")
        if task_id is not None and current_part:
            result[int(task_id)] = current_part
    return result


def _split_flagged_tasks(
    flagged_tasks: list[Task],
    task_part_map: dict[int, str],
    current_part: str,
) -> tuple[list[Task], list[Task]]:
    current = []
    other = []
    current_key = _part_key(current_part)
    for task in flagged_tasks:
        part = task_part_map.get(task.id)
        if part and _part_key(part) == current_key:
            current.append(task)
        else:
            other.append(task)
    return current, other


def _apply_project_overview(
    overview_file: File,
    *,
    locale: str,
    summary_text: str,
    current_part: str,
    current_part_update: str,
    current_tasks: list[Task],
    other_tasks: list[Task],
    recent_rows: list[dict],
    parts: list[str],
):
    labels = _overview_labels(locale)
    role_specs = [
        ("summary", "summary", {"text": summary_text}),
        ("current_part_header", "header", _part_header_content(current_part, True)),
        ("current_part_update", "text", {"text": current_part_update}),
        (
            "current_part_tasks_header",
            "header",
            {"text": labels["current_tasks"], "level": 3},
        ),
        ("current_part_tasks", "list", {"items": _task_items(current_tasks)}),
        (
            "other_part_tasks_header",
            "header",
            {"text": labels["other_tasks"], "level": 3},
        ),
        ("other_part_tasks", "list", {"items": _task_items(other_tasks)}),
        ("recent_progress", "table", {"rows": _recent_table_rows(recent_rows, labels)}),
        ("parts_header", "header", {"text": labels["parts"], "level": 3}),
        ("parts", "list", {"items": _part_items(parts, current_part)}),
    ]
    blocks = _active_blocks(overview_file.id)
    generated = []
    for order, (role, block_type, content) in enumerate(role_specs):
        block = _generated_block(overview_file, blocks, role, block_type)
        block.content = {
            **content,
            "generated_by": GENERATED_BY,
            "generated_role": role,
        }
        block.order_index = order
        flag_modified(block, "content")
        generated.append(block)

    generated_ids = {block.id for block in generated}
    order = len(role_specs)
    for block in blocks:
        if block.id in generated_ids:
            continue
        if (block.content or {}).get("generated_by") == GENERATED_BY:
            continue
        block.order_index = order
        order += 1
    db.session.flush()


def _generated_block(overview_file: File, blocks: list[Block], role: str, block_type: str):
    for block in blocks:
        content = block.content or {}
        if (
            content.get("generated_by") == GENERATED_BY
            and content.get("generated_role") == role
        ):
            block.type = block_type
            return block
    block = Block(file_id=overview_file.id, type=block_type, content={}, order_index=0)
    db.session.add(block)
    db.session.flush()
    blocks.append(block)
    return block


def _normalize_recent_rows(raw_rows, max_date_groups: int) -> list[dict]:
    rows = []
    for item in raw_rows:
        if not isinstance(item, dict):
            continue
        date = str(item.get("date") or "").strip()
        done = str(item.get("done") or item.get("summary") or "").strip()
        next_step = str(item.get("next") or item.get("next_step") or "").strip()
        if date or done or next_step:
            rows.append({"date": date, "done": done, "next": next_step})
    return rows[:max_date_groups]


def _recent_table_rows(recent_rows: list[dict], labels: dict[str, str]) -> list[list[str]]:
    rows = [[labels["date"], labels["done"], labels["next"]]]
    for item in recent_rows:
        rows.append([item.get("date") or "", item.get("done") or "", item.get("next") or ""])
    if len(rows) == 1:
        rows.append(["", "", ""])
    return rows


def _task_items(tasks: list[Task]) -> list[dict]:
    items = [{"text": task.title} for task in tasks if (task.title or "").strip()]
    return items or [{"text": ""}]


def _part_items(parts: list[str], current_part: str) -> list[dict]:
    current_key = _part_key(current_part)
    return [
        {
            "text": part,
            "is_current_part": _part_key(part) == current_key,
        }
        for part in parts
    ] or [{"text": ""}]


def _overview_labels(locale: str) -> dict[str, str]:
    if locale == "he":
        return {
            "current_tasks": "משימות מסומנות בחלק הנוכחי",
            "other_tasks": "משימות מסומנות מחלקים אחרים",
            "parts": "חלקי הפרויקט",
            "date": "תאריך",
            "done": "מה נעשה",
            "next": "המשך",
        }
    return {
        "current_tasks": "Flagged tasks in current part",
        "other_tasks": "Flagged tasks from other parts",
        "parts": "Project parts",
        "date": "Date",
        "done": "What happened",
        "next": "Forward",
    }


def _empty_documentation_text() -> str:
    return "=== DOCUMENTATION ===\n(empty)"


def _flagged_tasks_for_topic(topic_id: int) -> list[Task]:
    topic = db.session.get(Topic, int(topic_id))
    if topic is None:
        return []

    rows = (
        db.session.query(Task)
        .join(TaskView, TaskView.task_id == Task.id)
        .outerjoin(Block, Task.block_id == Block.id)
        .outerjoin(File, Block.file_id == File.id)
        .filter(TaskView.section_flag == IMPORTANT_SECTION_FLAG)
        .filter(Task.archived_at.is_(None))
        .filter(
            or_(
                File.topic_id == topic.id,
                TaskView.topic_key == topic.name,
            )
        )
        .order_by(Task.id)
        .all()
    )
    seen: set[int] = set()
    unique: list[Task] = []
    for task in rows:
        if task.id in seen:
            continue
        seen.add(task.id)
        unique.append(task)
    return unique


def _active_blocks(file_id: int) -> list[Block]:
    return (
        Block.query.filter_by(file_id=file_id)
        .filter(Block.archived_at.is_(None))
        .order_by(Block.order_index, Block.id)
        .all()
    )


def _block_text(block: Block) -> str:
    content = dict(block.content or {})
    if block.type in {"text", "header", "summary"}:
        return str(content.get("text") or "").strip()
    if block.type == "list":
        return "\n".join(
            str(item.get("text") or "").strip()
            for item in content.get("items") or []
            if str(item.get("text") or "").strip()
        )
    if block.type == "table":
        return "\n".join(
            " | ".join(str(cell).strip() for cell in row if str(cell).strip())
            for row in content.get("rows") or []
        )
    return ""


def _header_text(block: Block) -> str:
    return str((block.content or {}).get("text") or "").strip()


def _part_key(value) -> str:
    return " ".join(str(value or "").strip().casefold().split())
