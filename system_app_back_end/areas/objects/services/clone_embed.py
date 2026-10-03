"""Independent object copies, resolved from a clipboard pointer at paste time."""
from copy import deepcopy

from models import EntityTag, InformationPiece, Task, TaskList, ViewTaskMembership, db
from areas.objects.services.create_embed import create_embed_in_file


def clone_embed_in_file(source, file, *, block_index=None):
    """Copy content and presentation into fresh rows. Caller commits atomically.

    View assignments follow copied tasks, with fresh memberships and destination
    topic. Automation ownership and object connections are not duplicated.
    """
    info = db.session.get(InformationPiece, source.information_id) if source.information_id else None
    task_list = db.session.get(TaskList, source.task_list_id) if source.task_list_id else None
    clone = create_embed_in_file(
        file, type_=source.type,
        title=info.title if info else task_list.title if task_list else "",
        body=info.body if info else "",
        payload=deepcopy(source.payload), block_index=block_index,
    )
    clone.payload = deepcopy(source.payload)
    if info:
        db.session.get(InformationPiece, clone.information_id).metadata_ = deepcopy(info.metadata_)
    if task_list:
        for task in Task.query.filter_by(task_list_id=task_list.id).order_by(Task.list_order_index, Task.id).all():
            copied = Task(
                task_list_id=clone.task_list_id, title=task.title,
                title_spans=deepcopy(task.title_spans), status=task.status,
                due_date=task.due_date, list_order_index=task.list_order_index,
                archived_at=task.archived_at,
            )
            db.session.add(copied)
            db.session.flush()
            for membership in ViewTaskMembership.query.filter_by(task_id=task.id).all():
                peers = ViewTaskMembership.query.filter_by(view_id=membership.view_id).all()
                db.session.add(ViewTaskMembership(
                    task_id=copied.id, view_id=membership.view_id,
                    section_name=membership.section_name, section_flag=membership.section_flag,
                    topic_key=f"topic_{file.topic_id}",
                    order_index=max((m.order_index for m in peers), default=-1) + 1,
                    topic_order_index=max((m.topic_order_index for m in peers), default=-1) + 1,
                ))
    for tag in EntityTag.query.filter_by(entity_type="object", entity_id=source.id).all():
        db.session.add(EntityTag(entity_type="object", entity_id=clone.id, tag_id=tag.tag_id))
    db.session.flush()
    return clone
