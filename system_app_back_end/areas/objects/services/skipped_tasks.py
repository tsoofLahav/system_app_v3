"""Store skips and settle the task atomically; never create report files."""
from datetime import datetime
from models import db, File, Topic, TaskList, View, SkippedTask
from areas.objects.services.object_graph import file_id_for_task
from areas.automations.services.review_tracking import dismiss_task_reviews


def record_skip(task, window, section_name):
    if task.archived_at is not None or task.status != "active":
        return None
    previous = SkippedTask.query.filter_by(automation_id=window.id,
        window_opened_at=window.window_opened_at, task_id=task.id).first()
    if previous is None:
        view = db.session.get(View, window.view_id)
        file_id = file_id_for_task(task)
        file = db.session.get(File, file_id) if file_id else None
        topic = db.session.get(Topic, file.topic_id) if file else None
        if topic is None:
            from models import ViewTaskMembership
            membership = ViewTaskMembership.query.filter_by(view_id=view.id, task_id=task.id).first()
            key = str(membership.topic_key or "") if membership else ""
            if key.startswith("topic_") and key[6:].isdigit():
                candidate = db.session.get(Topic, int(key[6:]))
                if candidate and candidate.workspace_id == window.workspace_id:
                    topic = candidate
        task_list = db.session.get(TaskList, task.task_list_id) if task.task_list_id else None
        previous = SkippedTask(workspace_id=window.workspace_id, task_id=task.id,
            task_title=task.title, topic_id=topic.id if topic else None,
            topic_name=topic.name if topic else None, task_list_id=task.task_list_id,
            task_list_title=task_list.title if task_list else None,
            view_id=view.id, view_name=view.name, section_key=window.section_key,
            section_name=section_name, automation_id=window.id,
            window_opened_at=window.window_opened_at, skipped_at=datetime.utcnow())
        db.session.add(previous)
    dismiss_task_reviews(task)
    task.status = "skipped"
    db.session.flush()
    return previous
