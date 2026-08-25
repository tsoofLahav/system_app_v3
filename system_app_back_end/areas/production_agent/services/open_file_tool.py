"""Build the `open_file` tool payload for the production agent.

Returns agent text plus minimal type-specific extras — never ORM dumps.
Archive files are readable; writes are rejected elsewhere in the runner.
"""

from __future__ import annotations

from typing import Any

from models import File, ObjectEmbed, Topic, TopicType, db
from areas.files.services.document_agent_text import (
    document_to_agent_text,
    load_objects_by_id,
)
from areas.objects.services.object_graph import connection_dicts_for_object


def build_open_file_payload(file: File) -> dict[str, Any]:
    objects_by_id = load_objects_by_id(file.id)
    document_plain = document_to_agent_text(
        file.document_json or "",
        objects_by_id=objects_by_id,
    )
    return {
        "id": file.id,
        "name": file.name,
        "topic_id": file.topic_id,
        "topic": _topic_name(file.topic_id),
        "topic_type": _topic_type_name(file.topic_id),
        "archived": file.archived_at is not None,
        "document_plain": document_plain,
        "document_lines": [
            {"line": i, "text": row}
            for i, row in enumerate(document_plain.splitlines(), start=1)
        ],
        "object_extras": _object_extras(file.id, objects_by_id),
    }


def _topic_name(topic_id: int | None) -> str:
    """The agent picks targets by topic, so every opened file names its topic."""
    if not topic_id:
        return ""
    topic = db.session.get(Topic, int(topic_id))
    return (topic.name if topic else "") or ""


def _topic_type_name(topic_id: int | None) -> str:
    if not topic_id:
        return ""
    topic = db.session.get(Topic, int(topic_id))
    if topic is None or not topic.topic_type_id:
        return ""
    row = db.session.get(TopicType, int(topic.topic_type_id))
    return (row.name if row else "") or ""


def _object_extras(
    file_id: int,
    objects_by_id: dict[int, dict[str, Any]],
) -> list[dict[str, Any]]:
    """Minimal per-object extras. Omit entries with nothing useful."""
    extras: list[dict[str, Any]] = []
    for object_id, obj in objects_by_id.items():
        obj_type = obj.get("type")
        if obj_type == "info":
            entry = _info_extra(object_id, obj)
            if entry:
                extras.append(entry)
        # task_list / image / graph: usually none (content is in the fence)
    return extras


def _info_extra(object_id: int, obj: dict[str, Any]) -> dict[str, Any] | None:
    info = obj.get("information") or {}
    title = (info.get("title") or "").strip() or None
    links = _info_links(object_id)
    if not title and not links:
        return None
    entry: dict[str, Any] = {
        "object_id": object_id,
        "type": "info",
    }
    if title:
        entry["title"] = title
    if links:
        # Same word as in the system prompt: Links
        entry["Links"] = links
    return entry


def _info_links(object_id: int) -> list[dict[str, Any]]:
    embed = db.session.get(ObjectEmbed, object_id)
    if embed is None or embed.type != "info":
        return []
    out: list[dict[str, Any]] = []
    for conn in connection_dicts_for_object(embed):
        peer = conn.get("peer") or {}
        peer_id = peer.get("id")
        peer_type = peer.get("type")
        if peer_id is None or not peer_type:
            continue
        item: dict[str, Any] = {
            "id": peer_id,
            "type": peer_type,
            "title": peer.get("title") or f"{peer_type} #{peer_id}",
        }
        # related peers may sit on another file — useful for follow-up open_file
        if peer.get("file_id") is not None:
            item["file_id"] = peer["file_id"]
        kind = conn.get("kind") or "related"
        if kind == "description":
            item["kind"] = "description"
        out.append(item)
    return out
