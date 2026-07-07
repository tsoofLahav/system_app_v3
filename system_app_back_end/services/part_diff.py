"""Programmatic part ops — create (add-only) and diff fallback."""

from __future__ import annotations

import difflib

from services.unit_mapper import last_unit_id, slice_units_by_part


def default_item_kind(file_key: str) -> str:
    return "task" if file_key == "tasks" else "list_item"


def build_create_part_ops(units, part_name, content_items, file_key):
    anchor = last_unit_id(units)
    if not anchor:
        return []
    kind = default_item_kind(file_key)
    ops = [
        {
            "op": "add_after",
            "unit_id": anchor,
            "text": part_name,
            "kind": "header",
        }
    ]
    for item in content_items or []:
        text = str(item).strip()
        if text:
            ops.append(
                {
                    "op": "add_after",
                    "unit_id": anchor,
                    "text": text,
                    "kind": kind,
                }
            )
    return ops


def _normalize_ops(ops, valid_unit_ids):
    cleaned = []
    for op in ops or []:
        op_type = (op.get("op") or "").strip().lower()
        unit_id = op.get("unit_id")
        text = (op.get("text") or "").strip()
        if op_type in ("replace", "remove"):
            if unit_id in valid_unit_ids:
                cleaned.append(op)
        elif op_type == "add_after":
            if unit_id in valid_unit_ids and text:
                cleaned.append(op)
    return cleaned


def align_content_to_ops(units, part_name, new_items, file_key):
    """Programmatic fallback when AI diff returns invalid ops."""
    slice_units = slice_units_by_part(units, part_name)
    if not slice_units:
        return build_create_part_ops(units, part_name, new_items, file_key)

    old_items = []
    old_ids = []
    for unit in slice_units:
        if unit.get("kind") == "header":
            continue
        text = (unit.get("text") or "").strip()
        if text:
            old_items.append(text)
            old_ids.append(unit["id"])

    ops = []
    used_old = set()
    kind = default_item_kind(file_key)
    anchor = slice_units[-1]["id"]

    for new_text in new_items or []:
        new_text = str(new_text).strip()
        if not new_text:
            continue
        best_idx = None
        best_ratio = 0.0
        for index, old_text in enumerate(old_items):
            if index in used_old:
                continue
            ratio = difflib.SequenceMatcher(
                None, old_text.lower(), new_text.lower()
            ).ratio()
            if ratio > best_ratio:
                best_ratio = ratio
                best_idx = index
        if best_idx is not None and best_ratio >= 0.55:
            used_old.add(best_idx)
            if old_items[best_idx] != new_text:
                ops.append(
                    {
                        "op": "replace",
                        "unit_id": old_ids[best_idx],
                        "text": new_text,
                    }
                )
        else:
            ops.append(
                {
                    "op": "add_after",
                    "unit_id": anchor,
                    "text": new_text,
                    "kind": kind,
                }
            )

    return ops


def sanitize_diff_ops(ops, units, part_name, new_items, file_key):
    valid = {unit["id"] for unit in units}
    cleaned = _normalize_ops(ops, valid)
    if cleaned:
        return cleaned
    return align_content_to_ops(units, part_name, new_items, file_key)
