"""Validate and normalize AI unit operations."""

from __future__ import annotations


def normalize_ops(raw_ops) -> list[dict]:
    result = []
    for op in raw_ops or []:
        if not isinstance(op, dict):
            continue
        op_type = (op.get("op") or "").strip().lower()
        if op_type not in {"replace", "remove", "add_after"}:
            continue
        unit_id = op.get("unit_id")
        if not unit_id:
            continue
        normalized = {
            "op": op_type,
            "unit_id": str(unit_id),
            "text": (op.get("text") or "").strip(),
        }
        if op.get("reason"):
            normalized["reason"] = str(op.get("reason")).strip()
        if op.get("kind"):
            normalized["kind"] = op.get("kind")
        result.append(normalized)
    return result


def doc_implies_task_changes(documentation_text: str) -> bool:
    lowered = (documentation_text or "").lower()
    hints = ("task", "todo", "משימ", "לעשות", "צריך", "need to", "should", "routine")
    return any(hint in lowered for hint in hints)
