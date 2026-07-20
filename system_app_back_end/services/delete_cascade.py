from sqlalchemy import case

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


def _task_row_blocks_for_task(task: Task) -> list[Block]:
    file_id = None
    if task.block_id is not None:
        list_block = db.session.get(Block, task.block_id)
        if list_block is not None:
            file_id = list_block.file_id
    if file_id is None:
        list_block_id = _list_block_id_for_task(task)
        if list_block_id is not None:
            list_block = db.session.get(Block, list_block_id)
            if list_block is not None:
                file_id = list_block.file_id

    query = Block.query.filter_by(type="task").filter(Block.archived_at.is_(None))
    if file_id is not None:
        query = query.filter_by(file_id=file_id)
    return query.all()


def _compact_list_order(list_block_id: int) -> None:
    tasks = (
        Task.query.filter(
            Task.block_id == list_block_id,
            Task.archived_at.is_(None),
        )
        .order_by(
            case((Task.status == "done", 1), else_=0),
            Task.list_order_index,
            Task.id,
        )
        .all()
    )
    for index, task in enumerate(tasks):
        task.list_order_index = index
    db.session.flush()


def delete_task_cascade(task_id):
    task = db.session.get(Task, int(task_id))
    if task is None:
        return

    list_block_id = _list_block_id_for_task(task)
    row_blocks = []
    for block in _task_row_blocks_for_task(task):
        content = block.content or {}
        raw_task_id = content.get("task_id")
        if raw_task_id is None:
            continue
        try:
            if int(raw_task_id) == int(task_id):
                row_blocks.append(block)
        except (TypeError, ValueError):
            continue

    AutomationCompanionTask.query.filter_by(task_id=int(task_id)).delete(
        synchronize_session=False
    )
    TaskView.query.filter_by(task_id=int(task_id)).delete(synchronize_session=False)

    # Delete the task before row blocks so tasks.block_id never references a
    # row block we are removing (can happen after legacy drag drift).
    db.session.delete(task)
    db.session.flush()

    for block in row_blocks:
        db.session.delete(block)

    if list_block_id is not None:
        try:
            _compact_list_order(list_block_id)
        except Exception:
            db.session.expire_all()


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
