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


def _list_block_id_for_task(task: Task) -> int | None:
    block_id = task.block_id
    if block_id is None:
        return None
    block = db.session.get(Block, block_id)
    if block is None:
        return None
    if block.type == "task_list":
        return block.id
    if block.file_id is None:
        return None

    blocks = (
        Block.query.filter_by(file_id=block.file_id)
        .filter(Block.archived_at.is_(None))
        .order_by(Block.order_index, Block.id)
        .all()
    )
    row_index = next((index for index, item in enumerate(blocks) if item.id == block.id), None)
    if row_index is None:
        return None
    for index in range(row_index, -1, -1):
        if blocks[index].type == "task_list":
            return blocks[index].id
    return None


def _normalize_task_block_id(task: Task) -> None:
    list_block_id = _list_block_id_for_task(task)
    if list_block_id is None:
        return
    block = db.session.get(Block, task.block_id) if task.block_id is not None else None
    if block is None or block.type != "task_list":
        task.block_id = list_block_id


def _compact_list_order(list_block_id: int) -> None:
    remaining_ids = [task.id for task in tasks_for_list_block(list_block_id)]
    if remaining_ids:
        apply_list_task_order(list_block_id, remaining_ids)


def delete_task_cascade(task_id):
    task = db.session.get(Task, int(task_id))
    if task is None:
        return

    list_block_id = _list_block_id_for_task(task)
    _normalize_task_block_id(task)

    AutomationCompanionTask.query.filter_by(task_id=int(task_id)).delete(
        synchronize_session=False
    )
    TaskView.query.filter_by(task_id=int(task_id)).delete(synchronize_session=False)
    db.session.delete(task)
    db.session.flush()

    if list_block_id is not None:
        try:
            _compact_list_order(list_block_id)
        except Exception:
            pass


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
