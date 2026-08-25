"""Hidden per-type template topics — not a live working topic."""

from __future__ import annotations

from models import Topic, TopicType, db
from areas.files.services.clone_topic_content import clone_topic_content
from areas.files.services.template_slots import stamp_template_slots


def ensure_hidden_template(type_row: TopicType) -> Topic:
    """Return this type's hidden template topic, creating or detaching as needed."""
    existing = None
    if type_row.template_topic_id is not None:
        existing = db.session.get(Topic, type_row.template_topic_id)
        if existing is not None and existing.is_template:
            return existing

    dest = Topic(
        workspace_id=type_row.workspace_id,
        name=type_row.name,
        icon=None,
        color=None,
        order_index=0,
        file_layout="auto",
        topic_type_id=type_row.id,
        is_template=True,
    )
    db.session.add(dest)
    db.session.flush()

    if existing is not None:
        clone_topic_content(dest, existing, copy_identity=False)
        stamp_template_slots(dest)

    type_row.template_topic_id = dest.id
    db.session.flush()
    return dest


def detach_live_templates(workspace_id: int) -> bool:
    """If a type still points at a working topic, clone it into a hidden template."""
    changed = False
    types = TopicType.query.filter_by(workspace_id=workspace_id).all()
    for type_row in types:
        if type_row.template_topic_id is None:
            continue
        topic = db.session.get(Topic, type_row.template_topic_id)
        if topic is None or topic.is_template:
            continue
        ensure_hidden_template(type_row)
        changed = True
    return changed
