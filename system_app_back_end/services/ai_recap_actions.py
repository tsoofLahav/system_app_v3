from __future__ import annotations

from sqlalchemy import or_
from sqlalchemy.orm.attributes import flag_modified

from config import OPENAI_PROCESS_UPDATE_TEMPERATURE
from models import Block, File, Task, TaskView, Topic, db
from services.openai_service import chat_json
from services.task_view_flags import IMPORTANT_SECTION_FLAG
from services.unit_mapper import detect_language, flatten_doc_file_for_ai, flatten_units_for_ai, units_from_file

PROCESS_RECAP_UPDATE_PROMPT = """You update a process recap from plan and documentation.

## Goal

Write a short recap that answers:
- Where are we in the plan?
- What was done recently?
- What should be done next?

## Documentation table

Documentation entries may span multiple rows. Merge rows that share the same date into one summary line in `update_rows`.
Return only the most recent date groups (newest first), up to the limit given in the user message.

## Output

JSON only:
{
  "summary_text": "short narrative recap",
  "update_rows": [
    {"date": "17.6", "note": "merged summary for that date"},
    {"date": "15.6", "note": "..."}
  ]
}

`summary_text` should be concise prose (a few sentences).
`update_rows` should have one entry per distinct date, newest dates first.

Respond in the same language as the input files."""


def flagged_tasks_for_topic(topic_id: int) -> list[Task]:
    """Tasks with section_flag=important on any view, scoped to this process topic."""
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


def previous_summary_text(overview_file) -> str:
    blocks = _active_blocks(overview_file.id)
    for block in blocks:
        if block.type == "summary":
            return (block.content or {}).get("text") or ""
    return ""


def smart_process_recap_update(
    topic,
    overview_file,
    plan_file,
    doc_file,
    *,
    max_date_groups: int = 5,
):
    previous_summary = previous_summary_text(overview_file)
    plan_text = flatten_units_for_ai(units_from_file(plan_file.id), plan_file.name)
    doc_text = flatten_doc_file_for_ai(doc_file)
    flagged = flagged_tasks_for_topic(topic.id)
    flagged_lines = "\n".join(f"- {task.title}" for task in flagged if task.title)

    locale = detect_language(previous_summary, plan_text, doc_text, flagged_lines)
    lang_note = "Respond in Hebrew." if locale == "he" else "Respond in English."

    user_prompt = (
        f"Topic: {topic.name}\n"
        f"Max date groups in update_rows: {max_date_groups}\n\n"
        f"=== PREVIOUS RECAP SUMMARY ===\n{previous_summary or '(empty)'}\n\n"
        f"{plan_text}\n\n"
        f"{doc_text}\n\n"
        f"=== FLAGGED TASKS (any view) ===\n{flagged_lines or '(none)'}"
    )

    ai_result = chat_json(
        f"{PROCESS_RECAP_UPDATE_PROMPT}\n\n{lang_note}",
        user_prompt,
        temperature=OPENAI_PROCESS_UPDATE_TEMPERATURE,
    )

    summary_text = (ai_result.get("summary_text") or "").strip()
    update_rows = _normalize_update_rows(ai_result.get("update_rows") or [])
    apply_recap_update(
        overview_file,
        summary_text=summary_text,
        update_rows=update_rows,
        flagged_tasks=flagged,
        max_date_groups=max_date_groups,
    )
    return {
        "topic_id": topic.id,
        "overview_file_id": overview_file.id,
        "summary_length": len(summary_text),
        "update_row_count": len(update_rows[:max_date_groups]),
        "flagged_task_count": len(flagged),
    }


def apply_recap_update(
    overview_file,
    *,
    summary_text: str,
    update_rows: list[dict],
    flagged_tasks: list[Task],
    max_date_groups: int = 5,
):
    blocks = _active_blocks(overview_file.id)
    summary_block = _ensure_block(
        overview_file,
        blocks,
        "summary",
        {"text": ""},
        insert_before_types=("task_list", "table", "text"),
    )
    summary_block.content = {"text": summary_text}
    flag_modified(summary_block, "content")

    table_block = _ensure_block(
        overview_file,
        blocks,
        "table",
        {"rows": [["Date", "Note"], ["", ""]]},
        insert_before_types=("text",),
    )
    rows = [["Date", "Note"]]
    for item in update_rows[:max_date_groups]:
        date_label = str(item.get("date") or "").strip()
        note = str(item.get("note") or "").strip()
        if date_label or note:
            rows.append([date_label, note])
    if len(rows) == 1:
        rows.append(["", ""])
    table_block.content = {"rows": rows}
    flag_modified(table_block, "content")

    blocks = _active_blocks(overview_file.id)
    _sync_recap_task_list(overview_file, blocks, flagged_tasks)
    db.session.flush()


def _normalize_update_rows(raw_rows) -> list[dict]:
    normalized = []
    for item in raw_rows:
        if not isinstance(item, dict):
            continue
        date_label = str(item.get("date") or "").strip()
        note = str(item.get("note") or "").strip()
        if date_label or note:
            normalized.append({"date": date_label, "note": note})
    return normalized


def _active_blocks(file_id):
    return (
        Block.query.filter_by(file_id=file_id)
        .filter(Block.archived_at.is_(None))
        .order_by(Block.order_index, Block.id)
        .all()
    )


def _ensure_block(overview_file, blocks, block_type, default_content, insert_before_types=()):
    for block in blocks:
        if block.type == block_type:
            return block

    insert_index = len(blocks)
    for index, block in enumerate(blocks):
        if block.type in insert_before_types:
            insert_index = index
            break

    for block in blocks:
        if block.order_index is not None and block.order_index >= insert_index:
            block.order_index = (block.order_index or 0) + 1

    new_block = Block(
        file_id=overview_file.id,
        type=block_type,
        content=dict(default_content),
        order_index=insert_index,
    )
    db.session.add(new_block)
    db.session.flush()
    return new_block


def _sync_recap_task_list(overview_file, blocks, flagged_tasks: list[Task]):
    task_list_block = None
    for block in blocks:
        if block.type == "task_list":
            task_list_block = block
            break

    if task_list_block is None:
        task_list_block = Block(
            file_id=overview_file.id,
            type="task_list",
            content={},
            order_index=1,
        )
        db.session.add(task_list_block)
        db.session.flush()

    recap_task_blocks = [
        block
        for block in blocks
        if block.type == "task"
        and (block.content or {}).get("task_id") is not None
    ]
    recap_task_ids = [
        int((block.content or {})["task_id"])
        for block in recap_task_blocks
        if (block.content or {}).get("task_id") is not None
    ]

    for block in recap_task_blocks:
        db.session.delete(block)

    if recap_task_ids:
        for task in Task.query.filter(Task.id.in_(recap_task_ids)).all():
            if task.block_id == task_list_block.id:
                db.session.delete(task)

    order = (task_list_block.order_index or 0) + 1
    for source in flagged_tasks:
        title = (source.title or "").strip()
        if not title:
            continue
        task = Task(
            block_id=task_list_block.id,
            title=title,
            status=source.status if source.status in {"active", "done"} else "active",
        )
        db.session.add(task)
        db.session.flush()
        db.session.add(
            Block(
                file_id=overview_file.id,
                type="task",
                content={"task_id": task.id},
                order_index=order,
            )
        )
        order += 1
    db.session.flush()
