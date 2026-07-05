from sqlalchemy import or_

from models import Block, File, Topic, db


def _archived_files_base_query(topic: Topic):
    query = File.query.filter(File.topic_id == topic.id)
    if topic.archived_at is None:
        query = query.filter(File.archived_at.isnot(None))
    return query


def _header_texts_for_files(file_ids: list[int]) -> dict[int, list[str]]:
    if not file_ids:
        return {}
    blocks = (
        Block.query.filter(
            Block.file_id.in_(file_ids),
            Block.type == "header",
        )
        .order_by(Block.order_index, Block.id)
        .all()
    )
    result: dict[int, list[str]] = {}
    for block in blocks:
        text = (block.content or {}).get("text") if block.content else None
        if not text or not str(text).strip():
            continue
        result.setdefault(block.file_id, []).append(str(text).strip())
    return result


def _apply_search(query, q: str):
    pattern = f"%{q.strip()}%"
    scoped_file_ids = query.with_entities(File.id).subquery()
    header_file_ids = (
        db.session.query(Block.file_id)
        .filter(
            Block.file_id.in_(db.session.query(scoped_file_ids.c.id)),
            Block.type == "header",
            Block.content["text"].astext.ilike(pattern),
        )
        .distinct()
    )
    return query.filter(
        or_(
            File.name.ilike(pattern),
            File.id.in_(header_file_ids),
        )
    )


def list_archived_files_for_topic(
    topic_id: int,
    *,
    limit: int = 24,
    offset: int = 0,
    q: str | None = None,
):
    topic = db.session.get(Topic, topic_id)
    if topic is None:
        return None

    query = _archived_files_base_query(topic)
    if q and q.strip():
        query = _apply_search(query, q)

    total = query.count()
    if limit <= 0:
        return {
            "files": [],
            "total": total,
            "has_more": False,
            "header_texts_by_file_id": {},
        }

    files = (
        query.order_by(File.order_index, File.id)
        .offset(max(offset, 0))
        .limit(limit)
        .all()
    )
    file_ids = [file.id for file in files]
    return {
        "files": [file.to_dict() for file in files],
        "total": total,
        "has_more": offset + len(files) < total,
        "header_texts_by_file_id": _header_texts_for_files(file_ids),
    }
