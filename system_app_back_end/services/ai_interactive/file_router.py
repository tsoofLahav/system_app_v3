"""Pick the best target file within a topic for interactive AI tools."""

from __future__ import annotations

import json

from models import File
from services.openai_service import chat_json


def _topic_files(topic_id: int) -> list[File]:
    return (
        File.query.filter_by(topic_id=int(topic_id))
        .filter(File.archived_at.is_(None))
        .order_by(File.order_index, File.id)
        .all()
    )


def _doc_candidates(files: list[File]) -> list[dict]:
    docs = [f for f in files if f.type == "doc"]
    if not docs:
        docs = [f for f in files if f.type in ("overview", "protocol")]
    return [{"id": f.id, "name": f.name, "type": f.type} for f in docs]


def _pick_file(
    *,
    candidates: list[dict],
    text: str,
    locale: str,
    prompt: str,
) -> dict:
    if not candidates:
        raise ValueError("No matching files found in topic")
    if len(candidates) == 1:
        return candidates[0]

    lang_note = "Respond in Hebrew." if locale == "he" else "Respond in English."
    pick = chat_json(
        f"{prompt} {lang_note} Return JSON: "
        '{"file_id": number, "reason": string}',
        f"Content:\n{text}\n\nCandidates:\n{json.dumps(candidates, ensure_ascii=False)}",
    )
    file_id = int(pick["file_id"])
    matched = next((item for item in candidates if item["id"] == file_id), None)
    if matched is None:
        raise ValueError("AI picked an unknown file")
    matched = dict(matched)
    matched["reason"] = (pick.get("reason") or "").strip()
    return matched


def pick_tasks_file(*, topic_id: int, text: str, locale: str = "en") -> dict:
    files = _topic_files(topic_id)
    candidates = [
        {"id": f.id, "name": f.name, "type": f.type}
        for f in files
        if f.type == "tasks"
    ]
    return _pick_file(
        candidates=candidates,
        text=text,
        locale=locale,
        prompt="Pick the best tasks file for this captured item.",
    )


def pick_doc_file(*, topic_id: int, text: str, locale: str = "en") -> dict:
    files = _topic_files(topic_id)
    candidates = _doc_candidates(files)
    return _pick_file(
        candidates=candidates,
        text=text,
        locale=locale,
        prompt="Pick the best documentation file for this captured note.",
    )
