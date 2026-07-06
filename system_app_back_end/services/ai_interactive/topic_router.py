"""Route captured text to the best matching topic."""

from __future__ import annotations

import json

from models import Topic
from services.openai_service import chat_json


def _topic_candidates() -> list[dict]:
    topics = Topic.query.filter(Topic.archived_at.is_(None)).order_by(Topic.id).all()
    return [
        {"id": topic.id, "name": topic.name, "type": topic.type}
        for topic in topics
    ]


def match_text_to_topic(*, text: str, source_topic_id: int, locale: str = "en") -> dict:
    source = Topic.query.get(int(source_topic_id))
    if source is None:
        raise ValueError("Source topic not found")

    candidates = _topic_candidates()
    if not candidates:
        raise ValueError("No topics found")

    if len(candidates) == 1:
        only = candidates[0]
        return {
            "topic_id": only["id"],
            "topic_name": only["name"],
            "reason": "Only topic available",
        }

    lang_note = "Respond in Hebrew." if locale == "he" else "Respond in English."
    pick = chat_json(
        "The user captured a short note in one topic and wants it routed to the topic "
        "it most likely belongs to. Topics may be projects, processes, areas, or other "
        "organizational units. "
        f'{lang_note} Return JSON: {{"topic_id": number, "reason": string}}',
        f"Captured in topic: {source.name} (type: {source.type})\n"
        f"Content:\n{text}\n\n"
        f"All topics:\n{json.dumps(candidates, ensure_ascii=False)}",
    )

    topic_id = int(pick["topic_id"])
    matched = next((item for item in candidates if item["id"] == topic_id), None)
    if matched is None:
        raise ValueError("AI picked an unknown topic")

    return {
        "topic_id": matched["id"],
        "topic_name": matched["name"],
        "reason": (pick.get("reason") or "").strip(),
    }
