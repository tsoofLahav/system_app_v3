from models import (
    AiProposal,
    AutomationCompanionTask,
    Block,
    File,
    Part,
    Task,
    TaskResetAcknowledgement,
    TaskView,
    Topic,
    db,
)


from models import (
    AiProposal,
    AutomationCompanionTask,
    Block,
    File,
    Part,
    Task,
    TaskResetAcknowledgement,
    TaskView,
    Topic,
    db,
)
from services.task_list_order import apply_list_task_order, tasks_for_list_block


def _task_row_blocks_for_task(task: Task) -> list[Block]:
    file_id = None
    if task.block_id is not None:
        list_block = db.session.get(Block, task.block_id)
        if list_block is not None:
            file_id = list_block.file_id

    query = Block.query.filter_by(type="task").filter(Block.archived_at.is_(None))
    if file_id is not None:
        query = query.filter_by(file_id=file_id)
    return query.all()


def delete_task_cascade(task_id):
    task = db.session.get(Task, int(task_id))
    if task is None:
        return

    list_block_id = task.block_id

    AutomationCompanionTask.query.filter_by(task_id=int(task_id)).delete(
        synchronize_session=False
    )
    TaskView.query.filter_by(task_id=int(task_id)).delete(synchronize_session=False)

    for block in _task_row_blocks_for_task(task):
        content = block.content or {}
        raw_task_id = content.get("task_id")
        if raw_task_id is None:
            continue
        try:
            if int(raw_task_id) == int(task_id):
                db.session.delete(block)
        except (TypeError, ValueError):
            continue

    db.session.delete(task)
    db.session.flush()

    if list_block_id is not None:
        remaining_ids = [t.id for t in tasks_for_list_block(list_block_id)]
        if remaining_ids:
            apply_list_task_order(list_block_id, remaining_ids)


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

    Part.query.filter_by(topic_id=topic_id).delete(synchronize_session=False)

    Topic.query.filter_by(parent_id=topic_id).update(
        {Topic.parent_id: None},
        synchronize_session=False,
    )
    db.session.delete(topic)
