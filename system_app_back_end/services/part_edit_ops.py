"""Shared rules for line-level edit ops (process update + project part update)."""

from __future__ import annotations

from services.unit_mapper import slice_units_by_part

# Appended to prompts that return unit-level ops.
EDIT_OPS_RULES = """## Edit ops

Return only edits to existing units, using the unit IDs provided in the input.

Each op:
- op: "replace" | "remove" | "add_after"
- unit_id: from the file input (must match an existing unit)
- text: required for replace and add_after — the full new line as it should appear in the file

### When to use each op

- **replace** — revise an existing point. The log updates the meaning of that line. `text` replaces the old line in place.
- **add_after** — a genuinely new point that does not replace any existing line. Insert after `unit_id`.
- **remove** — drop a point that no longer applies.

Prefer replace when revising an existing point. Use add_after only when a new point is clearly needed. Do not use add_after for revisions.

For replace and add_after, `text` is the final line content — not a suggestion about what to do."""


def sanitize_part_edit_ops(ops, units, part_name):
    """Keep only ops that reference units inside this part slice."""
    slice_units = slice_units_by_part(units, part_name)
    valid_ids = {unit["id"] for unit in slice_units}
    cleaned = []
    for op in ops or []:
        if not isinstance(op, dict):
            continue
        op_type = (op.get("op") or "").strip().lower()
        unit_id = op.get("unit_id")
        text = (op.get("text") or "").strip()
        if op_type in ("replace", "remove"):
            if unit_id in valid_ids:
                cleaned.append({"op": op_type, "unit_id": unit_id, "text": text})
        elif op_type == "add_after":
            if unit_id in valid_ids and text:
                kind = (op.get("kind") or "").strip() or _default_kind(unit_id, slice_units)
                cleaned.append(
                    {
                        "op": "add_after",
                        "unit_id": unit_id,
                        "text": text,
                        "kind": kind,
                    }
                )
    return cleaned


def summarize_ops(ops):
    summary = {"replace": 0, "add_after": 0, "remove": 0}
    for op in ops or []:
        key = (op.get("op") or "").strip().lower()
        if key in summary:
            summary[key] += 1
    return summary


def _default_kind(unit_id, slice_units):
    for unit in slice_units:
        if unit.get("id") == unit_id:
            kind = (unit.get("kind") or "").strip()
            if kind == "task":
                return "task"
            break
    return "list_item"
