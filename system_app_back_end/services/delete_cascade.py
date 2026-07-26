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
    Topic,
    View,
    ViewTaskMembership,
    db,
)
from services.document_body import marker_for, remove_marker


def delete_task_cascade(task_id: int) -> None:
    task = db.session.get(Task, int(task_id))
    if task is None:
        return

    ViewTaskMembership.query.filter_by(task_id=task.id).delete(
        synchronize_session=False
    )
    embeds = ObjectEmbed.query.filter_by(task_id=task.id).all()
    for embed in embeds:
        delete_object_embed_cascade(embed, remove_from_body=True)
    db.session.delete(task)


def delete_object_embed_cascade(embed: ObjectEmbed, *, remove_from_body: bool) -> None:
    file = db.session.get(File, embed.file_id)
    if file and remove_from_body:
        if embed.type == "task" and embed.task_id:
            marker = marker_for("task", embed.task_id)
        elif embed.type == "information" and embed.information_id:
            marker = marker_for("information", embed.information_id)
        else:
            marker = None
        if marker:
            file.body = remove_marker(file.body or "", marker)

    if embed.type == "task" and embed.task_id:
        task = db.session.get(Task, embed.task_id)
        if task:
            ViewTaskMembership.query.filter_by(task_id=task.id).delete(
                synchronize_session=False
            )
            db.session.delete(task)
    elif embed.type == "information" and embed.information_id:
        info = db.session.get(InformationPiece, embed.information_id)
        if info:
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
