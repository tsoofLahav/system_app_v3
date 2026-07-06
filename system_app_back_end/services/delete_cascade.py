from models import (
    AiProposal,
    AutomationCompanionTask,
    Block,
    File,
    Task,
    TaskResetAcknowledgement,
    TaskView,
    Topic,
    db,
)


def delete_task_cascade(task_id):
    task = db.session.get(Task, task_id)
    if task is None:
        return

    AutomationCompanionTask.query.filter_by(task_id=task_id).delete(
        synchronize_session=False
    )
    TaskView.query.filter_by(task_id=task_id).delete(synchronize_session=False)
    db.session.delete(task)


def delete_file_cascade(file_id):
    file = db.session.get(File, file_id)
    if file is None:
        return

    blocks = Block.query.filter_by(file_id=file_id).all()
    block_ids = [block.id for block in blocks]

    if block_ids:
        tasks = Task.query.filter(Task.block_id.in_(block_ids)).all()
        for task in tasks:
            delete_task_cascade(task.id)

    for block in blocks:
        db.session.delete(block)

    AiProposal.query.filter_by(target_file_id=file_id).delete(
        synchronize_session=False
    )
    TaskResetAcknowledgement.query.filter_by(report_file_id=file_id).delete(
        synchronize_session=False
    )
    db.session.delete(file)


def delete_topic_cascade(topic_id):
    topic = db.session.get(Topic, topic_id)
    if topic is None:
        return

    AiProposal.query.filter_by(topic_id=topic_id).delete(synchronize_session=False)

    AutomationCompanionTask.query.filter_by(topic_id=topic_id).delete(
        synchronize_session=False
    )

    files = File.query.filter_by(topic_id=topic_id).all()
    for file in files:
        delete_file_cascade(file.id)

    Topic.query.filter_by(parent_id=topic_id).update(
        {Topic.parent_id: None},
        synchronize_session=False,
    )
    db.session.delete(topic)
