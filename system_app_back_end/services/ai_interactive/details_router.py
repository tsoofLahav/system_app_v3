"""Pick the best details block within a topic for a query."""

from __future__ import annotations

import json

from services.details_lookup import list_details_blocks_for_topic
from services.openai_service import chat_json


def pick_details_block(
    *,
    topic_id: int,
    query: str,
    locale: str = "en",
) -> dict:
    candidates = list_details_blocks_for_topic(topic_id)
    if not candidates:
        raise ValueError("No details blocks found in topic")

    if len(candidates) == 1:
        only = candidates[0]
        return {
            "block_id": only["block_id"],
            "title": only.get("title") or "",
            "text": only.get("text") or "",
            "reason": "Only details block in topic",
        }

    compact = [
        {
            "block_id": item["block_id"],
            "title": item.get("title") or "",
            "preview": item.get("text_preview") or "",
            "file_name": item.get("file_name") or "",
        }
        for item in candidates
    ]
    lang_note = "Respond in Hebrew." if locale == "he" else "Respond in English."
    pick = chat_json(
        "The user wants reusable details text (recipe, instructions, notes). "
        "Pick the details block that best matches their query. "
        f'{lang_note} Return JSON: {{"block_id": number, "reason": string}}',
        f"Query:\n{query.strip()}\n\n"
        f"Details blocks:\n{json.dumps(compact, ensure_ascii=False)}",
    )
    block_id = int(pick["block_id"])
    matched = next((item for item in candidates if item["block_id"] == block_id), None)
    if matched is None:
        raise ValueError("AI picked an unknown details block")
    return {
        "block_id": matched["block_id"],
        "title": matched.get("title") or "",
        "text": matched.get("text") or "",
        "reason": (pick.get("reason") or "").strip(),
    }
