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
from services.document_body import remove_object_nodes


def delete_task_cascade(task_id: int) -> None:
    task = db.session.get(Task, int(task_id))
    if task is None:
        return

    task_list_id = task.task_list_id
    ViewTaskMembership.query.filter_by(task_id=task.id).delete(
        synchronize_session=False
    )
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
        db.session.delete(task)
    task_list = db.session.get(TaskList, task_list_id)
    if task_list:
        db.session.delete(task_list)


def delete_object_embed_cascade(embed: ObjectEmbed, *, remove_from_body: bool) -> None:
    file = db.session.get(File, embed.file_id)
    if file and remove_from_body:
        file.body = remove_object_nodes(file.body or "", embed.id)

    if embed.type == "task_list" and embed.task_list_id:
        delete_task_list_cascade(embed.task_list_id)
    elif embed.type == "info" and embed.information_id:
        info = db.session.get(InformationPiece, embed.information_id)
        if info:
            Link.query.filter_by(
                source_type="info", source_id=info.id
            ).delete(synchronize_session=False)
            db.session.delete(info)

    db.session.delete(embed)


def delete_file_cascade(file_id: int) -> None:
    file = db.session.get(File, file_id)
    if file is None:
        return

    embeds = ObjectEmbed.query.filter_by(file_id=file_id).all()
    for embed in embeds:
        delete_object_embed_cascade(embed, remove_from_body=False)

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
    ViewTaskMembership.query.filter_by(view_id=view_id).delete(
        synchronize_session=False
    )
    view = db.session.get(View, view_id)
    if view:
        db.session.delete(view)


def delete_automation_cascade(automation_id: int) -> None:
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
