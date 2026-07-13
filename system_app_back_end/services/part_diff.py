"""Programmatic part ops — create (add-only) and update diff."""

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


def _part_content_lines(slice_units):
    items = []
    ids = []
    for unit in slice_units:
        if unit.get("kind") == "header":
            continue
        text = (unit.get("text") or "").strip()
        if text:
            items.append(text)
            ids.append(unit["id"])
    return items, ids


def _anchor_before_index(slice_units, old_ids, index):
    if index > 0:
        return old_ids[index - 1]
    for unit in slice_units:
        if unit.get("kind") == "header":
            return unit["id"]
    return old_ids[0] if old_ids else slice_units[-1]["id"]


def build_update_part_ops(units, part_name, new_items, file_key):
    """Map old vs new line arrays to replace, add_after, or remove ops."""
    slice_units = slice_units_by_part(units, part_name)
    if not slice_units:
        return build_create_part_ops(units, part_name, new_items, file_key)

    old_items, old_ids = _part_content_lines(slice_units)
    new_items = [str(item).strip() for item in (new_items or []) if str(item).strip()]
    if not old_items:
        return build_create_part_ops(units, part_name, new_items, file_key)

    if not new_items:
        return [{"op": "remove", "unit_id": unit_id} for unit_id in old_ids]

    matcher = difflib.SequenceMatcher(None, old_items, new_items, autojunk=False)
    ops = []
    kind = default_item_kind(file_key)

    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        if tag == "equal":
            continue
        if tag == "replace":
            overlap = min(i2 - i1, j2 - j1)
            for offset in range(overlap):
                old_text = old_items[i1 + offset]
                new_text = new_items[j1 + offset]
                if old_text != new_text:
                    ops.append(
                        {
                            "op": "replace",
                            "unit_id": old_ids[i1 + offset],
                            "text": new_text,
                        }
                    )
            for idx in range(i1 + overlap, i2):
                ops.append({"op": "remove", "unit_id": old_ids[idx]})
            anchor = (
                old_ids[i2 - 1]
                if i2 > i1
                else _anchor_before_index(slice_units, old_ids, i1)
            )
            for new_j in range(j1 + overlap, j2):
                ops.append(
                    {
                        "op": "add_after",
                        "unit_id": anchor,
                        "text": new_items[new_j],
                        "kind": kind,
                    }
                )
        elif tag == "delete":
            for idx in range(i1, i2):
                ops.append({"op": "remove", "unit_id": old_ids[idx]})
        elif tag == "insert":
            anchor = _anchor_before_index(slice_units, old_ids, i1)
            for new_j in range(j1, j2):
                ops.append(
                    {
                        "op": "add_after",
                        "unit_id": anchor,
                        "text": new_items[new_j],
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
    """Legacy fallback — prefer build_update_part_ops."""
    return build_update_part_ops(units, part_name, new_items, file_key)


def sanitize_diff_ops(ops, units, part_name, new_items, file_key):
    valid = {unit["id"] for unit in units}
    cleaned = _normalize_ops(ops, valid)
    if cleaned:
        return cleaned
    return build_update_part_ops(units, part_name, new_items, file_key)
