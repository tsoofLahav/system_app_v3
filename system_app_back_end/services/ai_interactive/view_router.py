"""Pick the best task view and section for a captured item."""

from __future__ import annotations

import json

from models import TaskView
from services.openai_service import chat_json

VIEW_TYPES = (
    "daily",
    "weekly",
    "monthly",
    "quarterly",
    "arrangements",
    "missions",
)


def _view_section_candidates() -> list[dict]:
    candidates: list[dict] = []
    for view_type in VIEW_TYPES:
        placeholders = (
            TaskView.query.filter_by(view_type=view_type)
            .filter(TaskView.task_id.is_(None))
            .filter(TaskView.section_name.isnot(None))
            .order_by(TaskView.order_index, TaskView.id)
            .all()
        )
        if placeholders:
            for placeholder in placeholders:
                candidates.append(
                    {
                        "view_type": view_type,
                        "section_name": placeholder.section_name,
                    }
                )
        else:
            candidates.append({"view_type": view_type, "section_name": None})
    return candidates


def pick_task_view_and_section(*, text: str, locale: str = "en") -> dict:
    candidates = _view_section_candidates()
    if not candidates:
        raise ValueError("No task views configured")

    if len(candidates) == 1:
        only = candidates[0]
        return {
            "view_type": only["view_type"],
            "section_name": only.get("section_name"),
            "reason": "Only view placement available",
        }

    lang_note = "Respond in Hebrew." if locale == "he" else "Respond in English."
    pick = chat_json(
        "The user captured a task item and it should appear in the best matching task "
        "view and section. Views are time horizons or planning boards; sections are "
        "columns within a view. "
        f'{lang_note} Return JSON: {{"view_type": string, "section_name": string|null, '
        '"reason": string}}',
        f"Task text:\n{text}\n\n"
        f"Placements:\n{json.dumps(candidates, ensure_ascii=False)}",
    )

    view_type = str(pick.get("view_type") or "").strip()
    if view_type not in VIEW_TYPES:
        raise ValueError("AI picked an unknown view")

    section_name = pick.get("section_name")
    if section_name is not None:
        section_name = str(section_name).strip() or None

    matched = next(
        (
            item
            for item in candidates
            if item["view_type"] == view_type
            and item.get("section_name") == section_name
        ),
        None,
    )
    if matched is None:
        section_options = [
            item.get("section_name")
            for item in candidates
            if item["view_type"] == view_type
        ]
        if section_name is not None and section_name not in section_options:
            section_name = section_options[0] if len(section_options) == 1 else None

    return {
        "view_type": view_type,
        "section_name": section_name,
        "reason": (pick.get("reason") or "").strip(),
    }
