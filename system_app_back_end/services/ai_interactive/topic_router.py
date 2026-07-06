"""Route captured text or files to the best matching topic."""

from __future__ import annotations

import json

from models import Block, File, Topic
from services.openai_service import chat_json


def _topic_candidates() -> list[dict]:
    topics = Topic.query.filter(Topic.archived_at.is_(None)).order_by(Topic.id).all()
    return [
        {"id": topic.id, "name": topic.name, "type": topic.type}
        for topic in topics
    ]


def _resolve_topic_pick(pick: dict, candidates: list[dict]) -> dict:
    topic_id = int(pick["topic_id"])
    matched = next((item for item in candidates if item["id"] == topic_id), None)
    if matched is None:
        raise ValueError("AI picked an unknown topic")
    return {
        "topic_id": matched["id"],
        "topic_name": matched["name"],
        "reason": (pick.get("reason") or "").strip(),
    }


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
    return _resolve_topic_pick(pick, candidates)


def _file_signal(file: File) -> str:
    lines = [
        f"File name: {file.name}",
        f"File type: {file.type}",
    ]
    source_topic = Topic.query.get(file.topic_id)
    if source_topic is not None:
        lines.append(
            f"Current topic: {source_topic.name} (type: {source_topic.type})"
        )

    blocks = (
        Block.query.filter_by(file_id=file.id)
        .filter(Block.archived_at.is_(None))
        .order_by(Block.order_index, Block.id)
        .limit(5)
        .all()
    )
    for block in blocks:
        content = block.content if isinstance(block.content, dict) else {}
        if block.type == "text":
            snippet = str(content.get("text") or "").strip()
            if snippet:
                lines.append(f"Text snippet: {snippet[:240]}")
        elif block.type == "header":
            snippet = str(content.get("text") or "").strip()
            if snippet:
                lines.append(f"Header: {snippet[:120]}")
        elif block.type == "table":
            rows = content.get("rows")
            if isinstance(rows, list) and rows:
                lines.append(f"Table rows: {len(rows)}")
    return "\n".join(lines)


def match_file_to_topic(*, file_id: int, source_topic_id: int, locale: str = "en") -> dict:
    file = File.query.get(int(file_id))
    if file is None:
        raise ValueError("File not found")
    if file.archived_at is not None:
        raise ValueError("Cannot move an archived file")

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
        "The user wants to move a whole file from one topic into another topic's "
        "additional files section. Pick the topic this file most likely belongs to. "
        f'{lang_note} Return JSON: {{"topic_id": number, "reason": string}}',
        f"Source topic: {source.name} (type: {source.type})\n"
        f"File to move:\n{_file_signal(file)}\n\n"
        f"All topics:\n{json.dumps(candidates, ensure_ascii=False)}",
    )
    return _resolve_topic_pick(pick, candidates)
