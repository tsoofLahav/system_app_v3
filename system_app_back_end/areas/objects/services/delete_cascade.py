from models import (
    Automation,
    AutomationRun,
    EntityTag,
    File,
    FileVersion,
    InformationPiece,
    Link,
    ObjectEmbed,
    Tag,
    Task,
    TaskList,
    Topic,
    View,
    ViewTaskMembership,
    db,
)
from areas.files.services.document_marker_text import embed_ids_in_text
from areas.files.services.document_v3 import remove_object_embeds
from areas.objects.services.object_graph import (
    delete_links_for_file,
    delete_links_for_object,
    delete_links_for_task,
)


def delete_task_cascade(task_id: int) -> None:
    task = db.session.get(Task, int(task_id))
    if task is None:
        return

    task_list_id = task.task_list_id
    ViewTaskMembership.query.filter_by(task_id=task.id).delete(
        synchronize_session=False
    )
    delete_links_for_task(task.id)
    db.session.delete(task)
    db.session.flush()

    if task_list_id is not None:
        remaining = Task.query.filter_by(task_list_id=task_list_id).all()
        for index, t in enumerate(
            sorted(
                remaining,
                key=lambda x: (
                    1 if x.status == "done" else 0,
                    x.list_order_index,
                    x.id,
                ),
            )
        ):
            t.list_order_index = index


def delete_task_list_cascade(task_list_id: int) -> None:
    tasks = Task.query.filter_by(task_list_id=task_list_id).all()
    for task in tasks:
        ViewTaskMembership.query.filter_by(task_id=task.id).delete(
            synchronize_session=False
        )
        delete_links_for_task(task.id)
        db.session.delete(task)
    task_list = db.session.get(TaskList, task_list_id)
    if task_list:
        db.session.delete(task_list)


def delete_object_embed_cascade(embed: ObjectEmbed, *, remove_from_document: bool) -> None:
    file = db.session.get(File, embed.file_id)
    if file and remove_from_document:
        file.document_json = remove_object_embeds(file.document_json or "", embed.id)

    delete_links_for_object(embed.id, embed.type)
    EntityTag.query.filter_by(
        entity_type="object", entity_id=embed.id
    ).delete(synchronize_session=False)

    if embed.type == "task_list" and embed.task_list_id:
        delete_task_list_cascade(embed.task_list_id)
    elif embed.type == "info" and embed.information_id:
        info = db.session.get(InformationPiece, embed.information_id)
        if info:
            # Legacy rows that still key by information_id.
            Link.query.filter_by(
                source_type="info", source_id=info.id
            ).delete(synchronize_session=False)
            db.session.delete(info)

    db.session.delete(embed)


def purge_unreferenced_embeds_for_file(file: File) -> list[int]:
    """Delete object rows for this file whose pointers are gone from the body.

    Super Editor can drop an embed node and PATCH ``document_json`` without
    calling ``DELETE /objects/:id``. The objects map would keep showing orphans
    unless we cascade-delete them here.
    """
    live_ids = embed_ids_in_text(file.document_json or "")
    embeds = ObjectEmbed.query.filter_by(file_id=file.id).all()
    removed: list[int] = []
    for embed in embeds:
        if embed.id in live_ids:
            continue
        delete_object_embed_cascade(embed, remove_from_document=False)
        removed.append(embed.id)
    return removed


def delete_file_cascade(file_id: int) -> None:
    file = db.session.get(File, file_id)
    if file is None:
        return

    delete_links_for_file(file_id)
    embeds = ObjectEmbed.query.filter_by(file_id=file_id).all()
    for embed in embeds:
        delete_object_embed_cascade(embed, remove_from_document=False)

    FileVersion.query.filter_by(file_id=file_id).delete(synchronize_session=False)
    db.session.delete(file)


def delete_topic_cascade(topic_id: int) -> None:
    topic = db.session.get(Topic, topic_id)
    if topic is None:
        return

    files = File.query.filter_by(topic_id=topic_id).all()
    for file in files:
        delete_file_cascade(file.id)

    EntityTag.query.filter_by(entity_type="topic", entity_id=topic_id).delete(
        synchronize_session=False
    )
    db.session.delete(topic)


def delete_view_cascade(view_id: int) -> None:
    from models import Automation

    for automation in Automation.query.filter_by(view_id=view_id).all():
        delete_automation_cascade(automation.id)
    ViewTaskMembership.query.filter_by(view_id=view_id).delete(
        synchronize_session=False
    )
    view = db.session.get(View, view_id)
    if view:
        db.session.delete(view)


def delete_automation_cascade(automation_id: int) -> None:
    from models import Task

    for task in Task.query.filter_by(source_automation_id=automation_id).all():
        delete_task_cascade(task.id)
    AutomationRun.query.filter_by(automation_id=automation_id).delete(
        synchronize_session=False
    )
    automation = db.session.get(Automation, automation_id)
    if automation:
        db.session.delete(automation)


def delete_tag_cascade(tag_id: int) -> None:
    EntityTag.query.filter_by(tag_id=tag_id).delete(synchronize_session=False)
    tag = db.session.get(Tag, tag_id)
    if tag:
        db.session.delete(tag)


def delete_workspace_cascade(workspace_id: int) -> None:
    for topic in Topic.query.filter_by(workspace_id=workspace_id).all():
        delete_topic_cascade(topic.id)
    for view in View.query.filter_by(workspace_id=workspace_id).all():
        delete_view_cascade(view.id)
    for automation in Automation.query.filter_by(workspace_id=workspace_id).all():
        delete_automation_cascade(automation.id)
    from models import Workspace

    Link.query.filter_by(workspace_id=workspace_id).delete(synchronize_session=False)
    Tag.query.filter_by(workspace_id=workspace_id).delete(synchronize_session=False)
    ws = db.session.get(Workspace, workspace_id)
    if ws:
        db.session.delete(ws)
