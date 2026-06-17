import re

from models import Block, Task, db


def units_from_file(file_id):
    blocks = (
        Block.query.filter_by(file_id=file_id)
        .filter(Block.archived_at.is_(None))
        .order_by(Block.order_index, Block.id)
        .all()
    )
    task_ids = []
    for block in blocks:
        if block.type == "task":
            task_id = (block.content or {}).get("task_id")
            if task_id:
                task_ids.append(int(task_id))
    tasks_by_id = {}
    if task_ids:
        for task in Task.query.filter(Task.id.in_(task_ids)).all():
            tasks_by_id[task.id] = task.title

    units = []
    for block in blocks:
        if block.type == "task_list":
            continue
        units.extend(_block_to_units(block, tasks_by_id))
    return units


def flatten_units_for_ai(units, title):
    lines = []
    for unit in units:
        text = (unit.get("text") or "").strip()
        if text:
            lines.append(f"[{unit['id']}] {text}")
    body = "\n".join(lines)
    return f"=== {title.upper()} ===\n{body}".strip()


def flatten_process_files_for_ai(plan_file, doc_file, tasks_file):
    return {
        "plan": flatten_units_for_ai(units_from_file(plan_file.id), plan_file.name),
        "documentation": flatten_units_for_ai(
            units_from_file(doc_file.id), doc_file.name
        ),
        "tasks": flatten_units_for_ai(units_from_file(tasks_file.id), tasks_file.name),
    }


def detect_language(*texts):
    combined = "\n".join(texts)
    hebrew = len(re.findall(r"[\u0590-\u05FF]", combined))
    latin = len(re.findall(r"[A-Za-z]", combined))
    return "he" if hebrew > latin else "en"


def apply_units_to_file(file, units):
    from models import Block, Task

    order = 0
    list_items = []
    checklist_items = []
    task_list_block = None
    has_tasks = any(unit.get("kind") == "task" for unit in units)

    if has_tasks:
        task_list_block = Block(
            file_id=file.id,
            type="task_list",
            content={},
            order_index=order,
        )
        db.session.add(task_list_block)
        db.session.flush()
        order += 1

    def flush_list():
        nonlocal order, list_items
        if not list_items:
            return
        db.session.add(
            Block(
                file_id=file.id,
                type="list",
                content={"items": list_items},
                order_index=order,
            )
        )
        order += 1
        list_items = []

    def flush_checklist():
        nonlocal order, checklist_items
        if not checklist_items:
            return
        db.session.add(
            Block(
                file_id=file.id,
                type="checklist",
                content={"items": checklist_items},
                order_index=order,
            )
        )
        order += 1
        checklist_items = []

    for unit in units:
        kind = unit.get("kind")
        text = (unit.get("text") or "").strip()
        if kind == "list_item":
            if text:
                list_items.append({"text": text})
            continue
        flush_list()
        if kind == "checklist_item":
            if text:
                checklist_items.append({"text": text, "done": False})
            continue
        flush_checklist()
        if kind == "task":
            if not text or task_list_block is None:
                continue
            task = Task(
                block_id=task_list_block.id,
                title=text,
                status="active",
            )
            db.session.add(task)
            db.session.flush()
            db.session.add(
                Block(
                    file_id=file.id,
                    type="task",
                    content={"task_id": task.id},
                    order_index=order,
                )
            )
            order += 1
            continue
        if kind == "header":
            db.session.add(
                Block(
                    file_id=file.id,
                    type="header",
                    content={"text": text, "level": 2},
                    order_index=order,
                )
            )
            order += 1
            continue
        if kind == "summary":
            db.session.add(
                Block(
                    file_id=file.id,
                    type="summary",
                    content={"text": text},
                    order_index=order,
                )
            )
            order += 1
            continue
        if kind == "paragraph" and text:
            db.session.add(
                Block(
                    file_id=file.id,
                    type="text",
                    content={"text": text},
                    order_index=order,
                )
            )
            order += 1
    flush_list()
    flush_checklist()
    db.session.flush()


def _block_to_units(block, tasks_by_id):
    content = dict(block.content or {})
    if block.type == "text":
        return [
            {
                "id": f"block:{block.id}",
                "kind": "paragraph",
                "text": (content.get("text") or "").strip(),
                "block_id": block.id,
            }
        ]
    if block.type == "header":
        return [
            {
                "id": f"block:{block.id}",
                "kind": "header",
                "text": (content.get("text") or "").strip(),
                "block_id": block.id,
            }
        ]
    if block.type == "summary":
        return [
            {
                "id": f"block:{block.id}",
                "kind": "summary",
                "text": (content.get("text") or "").strip(),
                "block_id": block.id,
            }
        ]
    if block.type == "list":
        units = []
        for index, item in enumerate(content.get("items") or []):
            text = (item.get("text") or "").strip()
            if not text:
                continue
            units.append(
                {
                    "id": f"block:{block.id}:item:{index}",
                    "kind": "list_item",
                    "text": text,
                    "block_id": block.id,
                    "path": ["items", index],
                }
            )
        return units
    if block.type == "checklist":
        units = []
        for index, item in enumerate(content.get("items") or []):
            text = (item.get("text") or "").strip()
            if not text:
                continue
            units.append(
                {
                    "id": f"block:{block.id}:item:{index}",
                    "kind": "checklist_item",
                    "text": text,
                    "block_id": block.id,
                    "path": ["items", index],
                }
            )
        return units
    if block.type == "task":
        task_id = content.get("task_id")
        title = tasks_by_id.get(int(task_id), "") if task_id else ""
        if not title:
            return []
        return [
            {
                "id": f"task:{task_id}",
                "kind": "task",
                "text": title,
                "block_id": block.id,
                "task_id": int(task_id),
            }
        ]
    return []
