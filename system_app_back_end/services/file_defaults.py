"""Factory-default block shapes for files (mirrors frontend FileBehaviorRegistry)."""

from __future__ import annotations

from models import Block

FILE_DEFAULT_BLOCK_SPECS: dict[str, list[tuple[str, dict]]] = {
    "plan": [
        ("text", {"text": ""}),
        (
            "list",
            {
                "items": [{"text": ""}],
                "list_style": "bullet",
            },
        ),
        ("text", {"text": ""}),
    ],
    "execution": [
        ("header", {"text": "", "level": 2}),
        (
            "list",
            {
                "items": [{"text": ""}],
                "list_style": "bullet",
            },
        ),
        ("text", {"text": ""}),
    ],
    "tasks": [
        ("task_list", {}),
    ],
}


def _normalize_list_content(content: dict) -> dict:
    items = content.get("items") or []
    normalized_items = []
    for item in items:
        if isinstance(item, dict):
            normalized_items.append({"text": str(item.get("text") or "").strip()})
        else:
            normalized_items.append({"text": str(item or "").strip()})
    result = {"items": normalized_items}
    if "list_style" in content:
        result["list_style"] = content.get("list_style")
    return result


def _block_matches_empty_spec(block: Block, block_type: str, spec_content: dict) -> bool:
    if block.type != block_type:
        return False
    if block.part_id is not None:
        return False

    content = block.content or {}

    if block_type == "text":
        return str(content.get("text") or "").strip() == ""

    if block_type == "summary":
        return str(content.get("text") or "").strip() == ""

    if block_type == "header":
        if content.get("part_id") is not None:
            return False
        if block.part_id is not None:
            return False
        return (
            str(content.get("text") or "").strip() == ""
            and int(content.get("level") or 2) == int(spec_content.get("level") or 2)
        )

    if block_type == "list":
        block_items = _normalize_list_content(content)["items"]
        spec_items = _normalize_list_content(spec_content)["items"]
        if not block_items:
            return not spec_items
        return block_items == spec_items and all(
            item.get("text") == "" for item in block_items
        )

    if block_type == "task_list":
        if content:
            return False
        return True

    if block_type == "task":
        task_id = content.get("task_id")
        if task_id is None:
            return True
        from models import Task, db

        task = db.session.get(Task, int(task_id))
        return task is not None and str(task.title or "").strip() == ""

    if block_type == "board":
        items = content.get("items") or []
        return len(items) == 0

    if block_type == "table":
        rows = content.get("rows") or []
        return all(
            all(str(cell or "").strip() == "" for cell in row)
            for row in rows
            if isinstance(row, list)
        )

    return not content


def _is_empty_trailing_text(block: Block) -> bool:
    return _block_matches_empty_spec(block, "text", {"text": ""})


def file_has_only_empty_defaults(file_type: str, blocks: list[Block]) -> bool:
    """True when the file still contains only factory placeholder blocks."""
    if file_type not in FILE_DEFAULT_BLOCK_SPECS:
        return False
    if not blocks:
        return False
    if any(block.part_id is not None for block in blocks):
        return False
    if any(
        (block.content or {}).get("part_id") is not None
        for block in blocks
        if block.type == "header"
    ):
        return False

    defaults = FILE_DEFAULT_BLOCK_SPECS[file_type]
    remaining = list(blocks)

    for block_type, spec_content in defaults:
        if not remaining:
            return False
        if not _block_matches_empty_spec(remaining[0], block_type, spec_content):
            return False
        remaining.pop(0)

    while remaining and _is_empty_trailing_text(remaining[0]):
        remaining.pop(0)

    return not remaining


def clear_file_blocks(file_id: int, blocks: list[Block]) -> None:
    from models import Task, db
    from services.delete_cascade import delete_task_cascade

    block_ids = [block.id for block in blocks]
    if block_ids:
        tasks = Task.query.filter(Task.block_id.in_(block_ids)).all()
        for task in tasks:
            delete_task_cascade(task.id)

    for block in blocks:
        db.session.delete(block)
    db.session.flush()
