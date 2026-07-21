"""Find details in a topic and return text for insertion at the cursor."""

from __future__ import annotations

from models import Topic, db
from services.ai_interactive.details_router import pick_details_block
from services.ai_interactive.topic_router import match_text_to_topic


def run_upload_details(*, text: str, source_topic_id: int, locale: str = "en") -> dict:
    route = match_text_to_topic(
        text=text,
        source_topic_id=source_topic_id,
        locale=locale,
    )
    target_topic_id = int(route["topic_id"])
    picked = pick_details_block(
        topic_id=target_topic_id,
        query=text,
        locale=locale,
    )

    title = picked.get("title") or ""
    body = picked.get("text") or ""
    insert_text = body if not title else f"{title}\n{body}".strip()

    target_topic = db.session.get(Topic, target_topic_id)
    return {
        "tool": "upload_details",
        "action": "insert",
        "result": insert_text,
        "details_title": title,
        "details_text": body,
        "details_block_id": picked["block_id"],
        "target_topic_id": target_topic_id,
        "target_topic_name": target_topic.name if target_topic else route.get("topic_name"),
        "route_reason": route.get("reason"),
        "details_reason": picked.get("reason"),
    }
