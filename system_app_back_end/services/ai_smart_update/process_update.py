"""Process smart update — shared implementation."""

from config import OPENAI_PROCESS_UPDATE_TEMPERATURE
from services.ai_smart_update.change_set_builder import build_process_change_set
from services.ai_smart_update.prompts import (
    OPS_OUTPUT_FORMAT,
    ROLE_DOC_READ_ONLY,
    ROLE_PLAN,
    ROLE_TASKS,
)
from services.ai_smart_update.unit_ops import doc_implies_task_changes, normalize_ops
from services.diff_engine import build_document_change_set
from services.openai_service import chat_json
from services.unit_mapper import (
    detect_language,
    flatten_process_files_for_ai,
    units_from_file,
)

SMART_PROCESS_UPDATE_PROMPT = f"""You update a personal process from weekly documentation.

## Files

{ROLE_PLAN}

{ROLE_TASKS}

{ROLE_DOC_READ_ONLY}

## What to do

1. Read PLAN, then DOCUMENTATION, then TASKS.
2. Decide what in PLAN and TASKS should change based on the documentation.
3. Return only edits to existing units, using the unit IDs provided.

For each edit, `text` is the new line as it should appear in the file — a direct replacement for that unit, not a suggestion about what to do.

## Output

{{"plan_ops":[],"tasks_ops":[]}}

{OPS_OUTPUT_FORMAT}

Prefer replace and edit over remove and add. Use remove or merge when it helps the plan stay organized and concise. Use add_after only when a new point is clearly needed.

Respond in the same language as the input files."""


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
        f"{SMART_PROCESS_UPDATE_PROMPT}\n\n{lang_note}",
        user_prompt,
        temperature=OPENAI_PROCESS_UPDATE_TEMPERATURE,
    )

    plan_units = units_from_file(plan_file.id)
    tasks_units = units_from_file(tasks_file.id)
    plan_ops = normalize_ops(ai_result.get("plan_ops"))
    tasks_ops = normalize_ops(ai_result.get("tasks_ops"))

    if not tasks_ops and doc_implies_task_changes(flattened["documentation"]):
        retry = chat_json(
            f"{SMART_PROCESS_UPDATE_PROMPT}\n\n{lang_note}\n"
            "The tasks file must be updated. Return tasks_ops only in JSON: "
            '{"tasks_ops":[]}',
            f"{flattened['tasks']}\n\nRevised plan context:\n"
            f"{flattened['plan']}\n\nDocumentation:\n{flattened['documentation']}",
            temperature=OPENAI_PROCESS_UPDATE_TEMPERATURE,
        )
        tasks_ops = normalize_ops(retry.get("tasks_ops")) or tasks_ops

    change_set = build_process_change_set(
        [
            build_document_change_set("plan", plan_file.name, plan_units, plan_ops),
            build_document_change_set("tasks", tasks_file.name, tasks_units, tasks_ops),
        ]
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
        "change_set": change_set,
    }
