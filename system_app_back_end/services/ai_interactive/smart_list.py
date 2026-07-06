"""Add captured text to the best matching tasks file."""

from __future__ import annotations

from models import File, Topic, db
from services.ai_interactive.file_router import pick_tasks_file
from services.ai_interactive.topic_router import match_text_to_topic
from services.ai_interactive.view_router import pick_task_view_and_section
from services.ai_interactive.writers import add_task_to_file


def run_smart_list(*, text: str, source_topic_id: int, locale: str = "en") -> dict:
    route = match_text_to_topic(
        text=text,
        source_topic_id=source_topic_id,
        locale=locale,
    )
    target_topic_id = int(route["topic_id"])
    file_pick = pick_tasks_file(topic_id=target_topic_id, text=text, locale=locale)
    file_id = int(file_pick["id"])
    placement = pick_task_view_and_section(text=text.strip(), locale=locale)

    task = add_task_to_file(
        file_id,
        text.strip(),
        view_type=placement["view_type"],
        section_name=placement.get("section_name"),
    )
    db.session.commit()

    target_file = db.session.get(File, file_id)
    target_topic = db.session.get(Topic, target_topic_id)
    return {
        "tool": "smart_list",
        "action": "write",
        "result": text.strip(),
        "target_topic_id": target_topic_id,
        "target_topic_name": target_topic.name if target_topic else route.get("topic_name"),
        "target_file_id": file_id,
        "target_file_name": target_file.name if target_file else None,
        "task_id": task.id,
        "target_kind": "task",
        "view_type": placement["view_type"],
        "section_name": placement.get("section_name"),
        "route_reason": route.get("reason"),
        "file_reason": file_pick.get("reason"),
        "view_reason": placement.get("reason"),
    }
