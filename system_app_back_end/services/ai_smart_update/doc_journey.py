"""Narrative doc row generation for project updates."""

from __future__ import annotations

from config import OPENAI_PROCESS_UPDATE_TEMPERATURE
from services.ai_smart_update.prompts import ROLE_DOC_JOURNEY
from services.openai_service import chat_json
from services.unit_mapper import detect_language, flatten_doc_file_for_ai


def generate_doc_journey_rows(*, log_text: str, doc_file, log_date: str) -> list[dict]:
    doc_context = flatten_doc_file_for_ai(doc_file) if doc_file else ""
    locale = detect_language(log_text, doc_context)
    lang_note = "Respond in Hebrew." if locale == "he" else "Respond in English."

    user_prompt = (
        f"Log date: {log_date}\n\n"
        f"=== EXISTING DOCUMENTATION ===\n{doc_context or '(empty)'}\n\n"
        f"=== LOG ===\n{log_text}"
    )

    result = chat_json(
        f"{ROLE_DOC_JOURNEY}\n\n{lang_note}",
        user_prompt,
        temperature=OPENAI_PROCESS_UPDATE_TEMPERATURE,
    )

    rows = []
    for row in result.get("rows") or []:
        if not isinstance(row, dict):
            continue
        text = (row.get("text") or "").strip()
        if not text:
            continue
        rows.append(
            {
                "date": (row.get("date") or log_date).strip(),
                "text": text,
            }
        )
    return rows
