"""Topic-scoped lookup for details blocks."""

from __future__ import annotations

from models import Block, File, Task, db


def _topic_id_for_file(file: File) -> int | None:
    if file.topic_id is not None:
        return file.topic_id
    return file.anchor_topic_id


def topic_id_for_task(task: Task) -> int | None:
    if task.block_id is None:
        return None
    list_block = db.session.get(Block, task.block_id)
    if list_block is None or list_block.file_id is None:
        return None
    file = db.session.get(File, list_block.file_id)
    if file is None:
        return None
    return _topic_id_for_file(file)


def details_title(content: dict | None) -> str:
    if not content:
        return ""
    return str(content.get("title") or "").strip()


def details_text(content: dict | None) -> str:
    if not content:
        return ""
    return str(content.get("text") or "").strip()


def text_preview(text: str, limit: int = 160) -> str:
    cleaned = " ".join(text.split())
    if len(cleaned) <= limit:
        return cleaned
    return cleaned[: limit - 1].rstrip() + "…"


def list_details_blocks_for_topic(topic_id: int) -> list[dict]:
    rows = (
        db.session.query(Block, File)
        .join(File, Block.file_id == File.id)
        .filter(Block.type == "details")
        .filter(Block.archived_at.is_(None))
        .filter(File.archived_at.is_(None))
        .filter(
            db.or_(
                File.topic_id == int(topic_id),
                File.anchor_topic_id == int(topic_id),
            )
        )
        .order_by(File.order_index, File.id, Block.order_index, Block.id)
        .all()
    )
    items = []
    for block, file in rows:
        content = block.content if isinstance(block.content, dict) else {}
        title = details_title(content)
        body = details_text(content)
        items.append(
            {
                "block_id": block.id,
                "file_id": file.id,
                "file_name": file.name,
                "title": title,
                "text": body,
                "text_preview": text_preview(body),
            }
        )
    return items


def validate_details_block_for_topic(
    details_block_id: int | None,
    *,
    topic_id: int,
) -> None:
    if details_block_id is None:
        return
    block = db.session.get(Block, int(details_block_id))
    if block is None or block.archived_at is not None:
        raise ValueError("details block not found")
    if block.type != "details":
        raise ValueError("block must be a details block")
    if block.file_id is None:
        raise ValueError("details block has no file")
    file = db.session.get(File, block.file_id)
    if file is None or file.archived_at is not None:
        raise ValueError("details block file not found")
    block_topic_id = _topic_id_for_file(file)
    if block_topic_id != int(topic_id):
        raise ValueError("details block must belong to the same topic as the task")


def validate_details_block_for_task(
    task: Task,
    details_block_id: int | None,
) -> None:
    topic_id = topic_id_for_task(task)
    if topic_id is None:
        raise ValueError("task has no topic")
    validate_details_block_for_topic(details_block_id, topic_id=topic_id)


def suggest_details_block_id(
    *,
    topic_id: int,
    query: str,
) -> int | None:
    candidates = list_details_blocks_for_topic(topic_id)
    if not candidates:
        return None
    needle = query.strip().casefold()
    if not needle:
        return candidates[0]["block_id"]

    scored: list[tuple[int, int]] = []
    for item in candidates:
        title = str(item.get("title") or "").casefold()
        preview = str(item.get("text_preview") or "").casefold()
        score = 0
        if title == needle:
            score += 100
        elif needle in title:
            score += 60
        elif title in needle:
            score += 40
        if needle in preview:
            score += 20
        if score > 0:
            scored.append((score, int(item["block_id"])))
    if not scored:
        return None
    scored.sort(key=lambda entry: (-entry[0], entry[1]))
    return scored[0][1]
