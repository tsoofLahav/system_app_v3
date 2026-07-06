"""Add captured text as a dated row in the best matching doc file."""

from __future__ import annotations

from datetime import datetime
from zoneinfo import ZoneInfo

from models import File, Topic, db
from services.ai_interactive.file_router import pick_doc_file
from services.ai_interactive.topic_router import match_text_to_topic
from services.ai_interactive.writers import insert_dated_doc_row
from services.automation_schedule import DEFAULT_AUTOMATION_TIMEZONE


def _today_in_timezone(timezone: str | None = None) -> str:
    tz_name = (timezone or "").strip() or DEFAULT_AUTOMATION_TIMEZONE
    try:
        tz = ZoneInfo(tz_name)
    except Exception:
        tz = ZoneInfo(DEFAULT_AUTOMATION_TIMEZONE)
    return datetime.now(tz).date().isoformat()


def run_smart_doc(*, text: str, source_topic_id: int, locale: str = "en") -> dict:
    cleaned = text.strip()
    route = match_text_to_topic(
        text=cleaned,
        source_topic_id=source_topic_id,
        locale=locale,
    )
    target_topic_id = int(route["topic_id"])
    file_pick = pick_doc_file(topic_id=target_topic_id, text=cleaned, locale=locale)
    file_id = int(file_pick["id"])
    entry_date = _today_in_timezone()

    table_block = insert_dated_doc_row(
        file_id=file_id,
        text=cleaned,
        entry_date=entry_date,
    )
    db.session.commit()

    target_file = db.session.get(File, file_id)
    target_topic = db.session.get(Topic, target_topic_id)
    return {
        "tool": "smart_doc",
        "action": "write",
        "result": cleaned,
        "date": entry_date,
        "target_topic_id": target_topic_id,
        "target_topic_name": target_topic.name if target_topic else route.get("topic_name"),
        "target_file_id": file_id,
        "target_file_name": target_file.name if target_file else None,
        "block_id": table_block.id,
        "target_kind": "doc_table",
        "route_reason": route.get("reason"),
        "file_reason": file_pick.get("reason"),
    }
