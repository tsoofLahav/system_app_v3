import json
import re

from models import Block, Task, db


def segments_from_file(file_id):
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

    segments = []
    for block in blocks:
        if block.type == "task_list":
            continue
        segment = _block_to_segment(block, tasks_by_id)
        if segment is not None:
            segments.append(segment)
    return segments


def flatten_file_for_ai(file_id, title):
    segments = segments_from_file(file_id)
    body = "\n\n".join(segment["label"] for segment in segments if segment.get("label"))
    return f"=== {title.upper()} ===\n{body}".strip()


def flatten_process_files_for_ai(plan_file, doc_file, tasks_file):
    return {
        "plan": flatten_file_for_ai(plan_file.id, plan_file.name),
        "documentation": flatten_file_for_ai(doc_file.id, doc_file.name),
        "tasks": flatten_file_for_ai(tasks_file.id, tasks_file.name),
    }


def detect_language(*texts):
    combined = "\n".join(texts)
    hebrew = len(re.findall(r"[\u0590-\u05FF]", combined))
    latin = len(re.findall(r"[A-Za-z]", combined))
    return "he" if hebrew > latin else "en"


def build_deltas(old_segments, new_segments):
    deltas = []
    count = max(len(old_segments), len(new_segments))
    for index in range(count):
        original = old_segments[index] if index < len(old_segments) else None
        suggested = new_segments[index] if index < len(new_segments) else None
        if _segments_equal(original, suggested):
            continue
        deltas.append(
            {
                "index": index,
                "original": original,
                "suggested": suggested,
            }
        )
    return deltas


def merge_segments(old_segments, deltas, decisions):
    delta_by_index = {delta["index"]: delta for delta in deltas}
    if not old_segments and not deltas:
        return []

    max_index = max(
        len(old_segments) - 1 if old_segments else -1,
        max((delta["index"] for delta in deltas), default=-1),
    )
    merged = []
    for index in range(max_index + 1):
        delta = delta_by_index.get(index)
        accepted = _decision(decisions, index)
        if delta and accepted and delta.get("suggested"):
            merged.append(delta["suggested"])
            continue
        if index < len(old_segments):
            merged.append(old_segments[index])
    return merged


def _decision(decisions, index):
    if not decisions:
        return False
    if str(index) in decisions:
        return bool(decisions[str(index)])
    if index in decisions:
        return bool(decisions[index])
    return False


def apply_segments_to_file(file, segments):
    from models import Block, Task

    has_tasks = any(segment.get("type") == "task" for segment in segments)
    task_list_block = None
    order = 0

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

    for segment in segments:
        seg_type = segment.get("type")
        content = segment.get("content") or {}
        if seg_type == "task":
            title = (content.get("title") or "").strip()
            if not title or task_list_block is None:
                continue
            task = Task(
                block_id=task_list_block.id,
                title=title,
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

        db.session.add(
            Block(
                file_id=file.id,
                type=seg_type,
                content=content,
                order_index=order,
            )
        )
        order += 1
    db.session.flush()


def segments_from_ai_payload(raw_segments):
    segments = []
    for index, item in enumerate(raw_segments or []):
        seg_type = item.get("type")
        content = item.get("content") or {}
        segment = {
            "id": item.get("id") or f"ai-{index}",
            "type": seg_type,
            "content": content,
            "label": item.get("label") or _label_for(seg_type, content),
        }
        segments.append(segment)
    return segments


def _block_to_segment(block, tasks_by_id):
    content = dict(block.content or {})
    if block.type in ("text", "summary", "header"):
        text = (content.get("text") or "").strip()
        return {
            "id": f"b{block.id}",
            "type": block.type,
            "content": content,
            "label": text,
        }
    if block.type == "list":
        return {
            "id": f"b{block.id}",
            "type": "list",
            "content": content,
            "label": _list_label(content),
        }
    if block.type == "table":
        return {
            "id": f"b{block.id}",
            "type": "table",
            "content": content,
            "label": _table_label(content.get("rows") or []),
        }
    if block.type == "task":
        task_id = content.get("task_id")
        title = tasks_by_id.get(int(task_id), "") if task_id else ""
        return {
            "id": f"b{block.id}",
            "type": "task",
            "content": {"title": title},
            "label": f"- [ ] {title}".strip(),
        }
    if block.type == "checklist":
        return {
            "id": f"b{block.id}",
            "type": "checklist",
            "content": content,
            "label": _checklist_label(content),
        }
    return {
        "id": f"b{block.id}",
        "type": block.type,
        "content": content,
        "label": json.dumps(content, ensure_ascii=False),
    }


def _label_for(seg_type, content):
    if seg_type in ("text", "summary", "header"):
        return (content.get("text") or "").strip()
    if seg_type == "list":
        return _list_label(content)
    if seg_type == "table":
        return _table_label(content.get("rows") or [])
    if seg_type == "task":
        title = (content.get("title") or "").strip()
        return f"- [ ] {title}".strip()
    if seg_type == "checklist":
        return _checklist_label(content)
    return json.dumps(content, ensure_ascii=False)


def _list_label(content):
    items = content.get("items") or []
    lines = []
    for item in items:
        text = (item.get("text") or "").strip()
        if text:
            lines.append(f"- {text}")
    return "\n".join(lines)


def _checklist_label(content):
    items = content.get("items") or []
    lines = []
    for item in items:
        text = (item.get("text") or "").strip()
        if not text:
            continue
        mark = "x" if item.get("done") else " "
        lines.append(f"- [{mark}] {text}")
    return "\n".join(lines)


def _table_label(rows):
    if not rows:
        return ""
    lines = []
    for row in rows:
        cells = [str(cell or "").strip() for cell in row]
        lines.append(" | ".join(cells))
    return "\n".join(lines)


def _segments_equal(left, right):
    if left is None and right is None:
        return True
    if left is None or right is None:
        return False
    return left.get("type") == right.get("type") and left.get("content") == right.get(
        "content"
    )
