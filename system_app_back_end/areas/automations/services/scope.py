"""What an automation is allowed to look at, and where its work lands.

Scope is one of three shapes:

    {"kind": "all"}                          the whole workspace
    {"kind": "topic", "topic_id": 3}         one topic
    {"kind": "topic_type", "tag": "process"} every topic tagged that way

A single-topic scope is also the **target**: a step that has to put something
somewhere (create a file) uses it, so the user does not name the same topic
twice. Any broader scope leaves the step to carry its own `topic_id`.

Rows written before this vocabulary existed hold `{"topic_ids": [...]}` and
still resolve, so nothing has to be migrated to be readable.
"""

from __future__ import annotations

from models import EntityTag, Tag, Topic, db

ALL = "all"
TOPIC = "topic"
TOPIC_TYPE = "topic_type"
SCOPE_KINDS = (ALL, TOPIC, TOPIC_TYPE)


def topic_ids_for_tag(workspace_id: int, tag_name: str) -> list[int]:
    rows = (
        db.session.query(Topic.id)
        .join(EntityTag, EntityTag.entity_id == Topic.id)
        .join(Tag, Tag.id == EntityTag.tag_id)
        .filter(
            EntityTag.entity_type == "topic",
            Tag.name == tag_name,
            Topic.workspace_id == workspace_id,
            Topic.archived_at.is_(None),
        )
        .order_by(Topic.id)
        .all()
    )
    return [row[0] for row in rows]


def resolve_scope(scope: dict | None, *, workspace_id: int) -> dict:
    """Stored scope → the `{workspace_id, topic_ids, file_ids}` shape the agent
    tools and the actions both read."""
    scope = dict(scope or {})
    resolved: dict = {"workspace_id": int(workspace_id)}
    kind = scope.get("kind")

    if kind == TOPIC and scope.get("topic_id") is not None:
        resolved["topic_ids"] = [int(scope["topic_id"])]
    elif kind == TOPIC_TYPE and scope.get("tag"):
        resolved["topic_ids"] = topic_ids_for_tag(workspace_id, str(scope["tag"]))
    elif kind in (None, ALL):
        # Legacy rows: explicit ids, no kind.
        if scope.get("topic_ids"):
            resolved["topic_ids"] = [int(i) for i in scope["topic_ids"]]
        if scope.get("file_ids"):
            resolved["file_ids"] = [int(i) for i in scope["file_ids"]]

    return resolved


def target_topic_id(resolved: dict) -> int | None:
    """The topic a placeless step should use — only when scope names exactly
    one, because "somewhere in these five" is not a destination."""
    topic_ids = resolved.get("topic_ids") or []
    return int(topic_ids[0]) if len(topic_ids) == 1 else None


def describe(scope: dict | None) -> str:
    """Short label for logs and run records."""
    scope = dict(scope or {})
    kind = scope.get("kind")
    if kind == TOPIC:
        return f"topic {scope.get('topic_id')}"
    if kind == TOPIC_TYPE:
        return f"topics tagged {scope.get('tag')!r}"
    if scope.get("topic_ids"):
        return f"topics {list(scope['topic_ids'])}"
    return "the whole workspace"
