"""Paginated archive listing: names, dates, heading search — not full bodies."""

from __future__ import annotations

import re

from models import File, Topic, db

_HEADING_RE = re.compile(r"^(#{1,6})\s+(.+)$")
_DEFAULT_PAGE = 24


def heading_texts_from_body(body: str | None) -> list[str]:
    """`#` … `######` lines in editor text. Not expanded object fences."""
    texts: list[str] = []
    for raw in (body or "").splitlines():
        line = raw.strip()
        if line.startswith("%%"):
            continue
        match = _HEADING_RE.match(line)
        if match:
            title = match.group(2).strip()
            if title:
                texts.append(title)
    return texts


def archived_file_matches_query(
    *,
    name: str | None,
    document_json: str | None,
    q: str,
) -> bool:
    needle = (q or "").strip().casefold()
    if not needle:
        return True
    if needle in (name or "").casefold():
        return True
    return any(needle in heading.casefold() for heading in heading_texts_from_body(document_json))


def list_archived_files_for_topic(
    topic_id: int,
    *,
    limit: int = _DEFAULT_PAGE,
    offset: int = 0,
    q: str | None = None,
) -> dict | None:
    topic = db.session.get(Topic, topic_id)
    if topic is None:
        return None

    query = (
        File.query.filter_by(topic_id=topic.id)
        .filter(File.archived_at.isnot(None))
        .order_by(File.archived_at.desc(), File.id.desc())
    )
    needle = (q or "").strip().casefold()
    if needle:
        files = [
            row
            for row in query.all()
            if archived_file_matches_query(
                name=row.name,
                document_json=row.document_json,
                q=needle,
            )
        ]
        total = len(files)
        if limit <= 0:
            page: list[File] = []
        else:
            start = max(offset, 0)
            page = files[start : start + limit]
    else:
        total = query.count()
        if limit <= 0:
            page = []
        else:
            page = query.offset(max(offset, 0)).limit(limit).all()

    headings = {
        str(row.id): heading_texts_from_body(row.document_json) for row in page
    }
    return {
        "files": [row.to_dict(include_document=False) for row in page],
        "total": total,
        "has_more": (max(offset, 0) + len(page)) < total,
        "heading_texts_by_file_id": headings,
    }
