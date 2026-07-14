"""Block-segment model for plan/execution part content round-trips."""

from __future__ import annotations

TEXT_BLOCK_KINDS = frozenset({"text", "summary"})
LIST_BLOCK_KIND = "list"


def segment_id_for(key: str, index: int) -> str:
    return f"seg:{key}:{index}"


def segment_anchor_id(key: str, index: int) -> str:
    return f"{segment_id_for(key, index)}:anchor"


def block_to_segment_units(block, tasks_by_id: dict | None = None) -> list[dict]:
    """One paragraph unit per text block; one list_item unit per list row."""
    tasks_by_id = tasks_by_id or {}
    content = dict(block.content or {})
    block_id = block.id

    if block.type in TEXT_BLOCK_KINDS:
        text = (content.get("text") or "").strip()
        if not text:
            return []
        return [
            {
                "id": f"block:{block_id}:text",
                "kind": "paragraph",
                "text": text,
                "block_id": block_id,
                "segment_id": f"block:{block_id}",
            }
        ]

    if block.type == LIST_BLOCK_KIND:
        units = []
        for index, item in enumerate(content.get("items") or []):
            text = (item.get("text") or "").strip()
            if not text:
                continue
            units.append(
                {
                    "id": f"block:{block_id}:item:{index}",
                    "kind": "list_item",
                    "text": text,
                    "block_id": block_id,
                    "segment_id": f"block:{block_id}",
                    "path": ["items", index],
                }
            )
        return units

    if block.type == "task":
        task_id = content.get("task_id")
        title = tasks_by_id.get(int(task_id), "") if task_id else ""
        if not title:
            return []
        return [
            {
                "id": f"task:{task_id}",
                "kind": "task",
                "text": title,
                "block_id": block_id,
                "segment_id": f"block:{block_id}",
                "task_id": int(task_id),
            }
        ]

    return []


def segments_from_part_blocks(blocks, *, tasks_by_id: dict | None = None) -> list[dict]:
    """Read ordered text/list segments from part content blocks."""
    tasks_by_id = tasks_by_id or {}
    segments = []

    for block in blocks:
        if block.type in ("header", "task_list"):
            continue

        if block.type in TEXT_BLOCK_KINDS:
            units = block_to_segment_units(block, tasks_by_id)
            if units:
                segments.append(
                    {
                        "block_kind": "text",
                        "segment_id": f"block:{block.id}",
                        "units": units,
                    }
                )
            continue

        if block.type == LIST_BLOCK_KIND:
            units = block_to_segment_units(block, tasks_by_id)
            if units:
                segments.append(
                    {
                        "block_kind": "list",
                        "segment_id": f"block:{block.id}",
                        "units": units,
                    }
                )
            continue

        if block.type == "task":
            units = block_to_segment_units(block, tasks_by_id)
            if units:
                segments.append(
                    {
                        "block_kind": "task",
                        "segment_id": f"block:{block.id}",
                        "units": units,
                    }
                )

    return segments


def segments_to_units(segments: list[dict]) -> list[dict]:
    result = []
    for segment in segments or []:
        for unit in segment.get("units") or []:
            result.append(dict(unit))
    return result


def units_to_segments(units: list[dict]) -> list[dict]:
    """Group flat units into segments by segment_id or block_id."""
    segments = []
    current_id = None
    current_kind = None
    current_units = []

    def flush():
        nonlocal current_id, current_kind, current_units
        if not current_units:
            current_id = None
            current_kind = None
            return
        segments.append(
            {
                "block_kind": current_kind or _infer_block_kind(current_units[0]),
                "segment_id": current_id,
                "units": current_units,
            }
        )
        current_units = []
        current_id = None
        current_kind = None

    for unit in units or []:
        unit = dict(unit)
        seg_id = unit.get("segment_id") or unit.get("block_id")
        if seg_id is None:
            flush()
            segments.append(
                {
                    "block_kind": _infer_block_kind(unit),
                    "segment_id": unit.get("id"),
                    "units": [unit],
                }
            )
            continue

        seg_key = str(seg_id)
        kind = _infer_block_kind(unit)
        if current_id is not None and seg_key != current_id:
            flush()
        if not current_units:
            current_id = seg_key
            current_kind = kind
        current_units.append(unit)

    flush()
    return segments


def _infer_block_kind(unit: dict) -> str:
    kind = unit.get("kind")
    if kind == "list_item":
        return "list"
    if kind == "task":
        return "task"
    return "text"


def plan_segments_from_ai(plan: dict | None) -> list[dict]:
    plan = plan or {}
    intro = str(plan.get("intro") or "").strip()
    points = [str(p).strip() for p in plan.get("points") or [] if str(p).strip()]
    segments = []
    index = 0

    if intro:
        segments.append(
            {
                "block_kind": "text",
                "segment_id": segment_id_for("plan", index),
                "items": [intro],
                "item_kinds": ["paragraph"],
            }
        )
        index += 1

    if points:
        segments.append(
            {
                "block_kind": "list",
                "segment_id": segment_id_for("plan", index),
                "items": points,
                "item_kinds": ["list_item"] * len(points),
            }
        )

    return segments


def execution_segments_from_ai(sections: list | None) -> list[dict]:
    segments = []
    index = 0
    for entry in sections or []:
        if not isinstance(entry, dict):
            continue
        text = str(entry.get("text") or "").strip()
        subpoints = [
            str(p).strip() for p in entry.get("subpoints") or [] if str(p).strip()
        ]
        if text:
            segments.append(
                {
                    "block_kind": "text",
                    "segment_id": segment_id_for("execution", index),
                    "items": [text],
                    "item_kinds": ["paragraph"],
                }
            )
            index += 1
        if subpoints:
            segments.append(
                {
                    "block_kind": "list",
                    "segment_id": segment_id_for("execution", index),
                    "items": subpoints,
                    "item_kinds": ["list_item"] * len(subpoints),
                }
            )
            index += 1
    return segments


def task_segment_from_ai(task_items: list | None) -> list[dict]:
    items = [str(t).strip() for t in task_items or [] if str(t).strip()]
    if not items:
        return []
    return [
        {
            "block_kind": "task",
            "segment_id": segment_id_for("tasks", 0),
            "items": items,
            "item_kinds": ["task"] * len(items),
        }
    ]
