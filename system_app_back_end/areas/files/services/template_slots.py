"""Stable keys so automations can find “the doc file” after a rename."""

from __future__ import annotations

import re

from sqlalchemy.orm.attributes import flag_modified

from models import File


_SLUG = re.compile(r"[^a-z0-9]+")


def slot_key_from_name(name: str, *, file_id: int) -> str:
    slug = _SLUG.sub("-", (name or "").strip().lower()).strip("-")
    if not slug:
        return f"file-{int(file_id)}"
    return slug[:40]


def stamp_template_slots(topic) -> None:
    """Give each live file a `meta.template_slot` if it does not have one."""
    files = (
        File.query.filter_by(topic_id=topic.id, archived_at=None)
        .order_by(File.order_index, File.id)
        .all()
    )
    used: set[str] = set()
    for file in files:
        meta = dict(file.meta or {})
        slot = str(meta.get("template_slot") or "").strip()
        if not slot:
            slot = slot_key_from_name(file.name, file_id=file.id)
        base = slot
        n = 2
        while slot in used:
            slot = f"{base}-{n}"
            n += 1
        used.add(slot)
        if meta.get("template_slot") != slot:
            meta["template_slot"] = slot
            file.meta = meta
            flag_modified(file, "meta")
