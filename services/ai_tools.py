import json
import os
import uuid
from urllib.request import urlopen

from flask import current_app

from models import Block, File, Task, Topic, db
from services.openai_service import chat_json, chat_text, generate_image


def _next_order(file_id: int) -> int:
    last = (
        Block.query.filter_by(file_id=file_id)
        .order_by(Block.order_index.desc(), Block.id.desc())
        .first()
    )
    if last is None or last.order_index is None:
        return 0
    return last.order_index + 1


def _append_text_block(file_id: int, text: str) -> Block:
    block = Block(
        file_id=file_id,
        type="text",
        content={"text": text},
        order_index=_next_order(file_id),
    )
    db.session.add(block)
    db.session.flush()
    return block


def _ensure_task_list_block(file_id: int) -> Block:
    existing = (
        Block.query.filter_by(file_id=file_id, type="task_list")
        .order_by(Block.id)
        .first()
    )
    if existing:
        return existing
    block = Block(
        file_id=file_id,
        type="task_list",
        content={},
        order_index=_next_order(file_id),
    )
    db.session.add(block)
    db.session.flush()
    return block


def _add_task_to_file(file_id: int, title: str) -> Task:
    list_block = _ensure_task_list_block(file_id)
    task = Task(block_id=list_block.id, title=title, status="active")
    db.session.add(task)
    db.session.flush()
    task_block = Block(
        file_id=file_id,
        type="task",
        content={"task_id": task.id},
        order_index=_next_order(file_id),
    )
    db.session.add(task_block)
    db.session.flush()
    return task



def _save_image_from_url(url: str) -> str:
    upload_folder = current_app.config["UPLOAD_FOLDER"]
    os.makedirs(upload_folder, exist_ok=True)
    filename = f"ai_{uuid.uuid4().hex[:10]}.png"
    path = os.path.join(upload_folder, filename)
    with urlopen(url) as resp, open(path, "wb") as out:
        out.write(resp.read())
    return f"/images/{filename}"


def _topic_files(topic_id: int) -> list[File]:
    return (
        File.query.filter_by(topic_id=topic_id)
        .filter(File.archived_at.is_(None))
        .order_by(File.order_index, File.id)
        .all()
    )


def _blocks_for_files(file_ids: list[int]) -> list[Block]:
    if not file_ids:
        return []
    return (
        Block.query.filter(Block.file_id.in_(file_ids))
        .filter(Block.archived_at.is_(None))
        .order_by(Block.file_id, Block.order_index, Block.id)
        .all()
    )


def _doc_candidates(files: list[File]) -> list[dict]:
    docs = [f for f in files if f.type == "doc"]
    if not docs:
        docs = [f for f in files if f.type in ("overview", "protocol")]
    return [{"id": f.id, "name": f.name, "type": f.type} for f in docs]


def _all_list_candidates() -> list[dict]:
    """All task files across every topic (capture-first routing)."""
    topics = Topic.query.filter(Topic.archived_at.is_(None)).order_by(Topic.id).all()
    topic_by_id = {t.id: t for t in topics}

    candidates: list[dict] = []

    task_files = (
        File.query.filter_by(type="tasks")
        .filter(File.archived_at.is_(None))
        .order_by(File.topic_id, File.order_index, File.id)
        .all()
    )
    for f in task_files:
        topic = topic_by_id.get(f.topic_id)
        topic_name = topic.name if topic else "unknown"
        candidates.append(
            {
                "kind": "tasks_file",
                "file_id": f.id,
                "topic_id": f.topic_id,
                "topic_name": topic_name,
                "topic_type": topic.type if topic else None,
                "name": f.name,
                "block_id": None,
                "label": f"{topic_name} → {f.name}",
            }
        )

    return candidates


def _data_snippets(files: list[File], blocks: list[Block]) -> str:
    parts = []
    data_file_ids = {f.id for f in files if f.type == "data"}
    for b in blocks:
        if b.file_id not in data_file_ids:
            continue
        if b.type == "table":
            parts.append(json.dumps(b.content, ensure_ascii=False))
        elif b.type == "measurement":
            parts.append(json.dumps(b.content, ensure_ascii=False))
    return "\n".join(parts)[:8000]


def run_tool(tool: str, topic_id: int, context: dict, locale: str = "en") -> dict:
    topic = Topic.query.get(topic_id)
    if topic is None:
        raise ValueError("Topic not found")

    text = (context.get("text") or "").strip()
    if not text and tool not in ("review", "create_graph"):
        raise ValueError("No context text provided")

    files = _topic_files(topic_id)
    file_ids = [f.id for f in files]
    blocks = _blocks_for_files(file_ids)
    lang_note = "Respond in Hebrew." if locale == "he" else "Respond in English."

    if tool == "consult":
        answer = chat_text(
            f"You are a concise assistant. Answer briefly in 2-4 sentences. {lang_note}",
            f"Context:\n{text}\n\nProvide a short, helpful response about this content.",
            max_tokens=300,
        )
        return {"tool": tool, "action": "display", "result": answer}

    if tool == "summarize_to_doc":
        candidates = _doc_candidates(files)
        if not candidates:
            raise ValueError("No documentation file found in this topic")

        pick = chat_json(
            "Pick the best documentation file for a summary. Return JSON: "
            '{"file_id": number, "reason": string}',
            f"Context to summarize:\n{text}\n\nCandidates:\n{json.dumps(candidates)}",
        )
        file_id = int(pick.get("file_id") or candidates[0]["id"])
        summary = chat_text(
            f"Summarize clearly in 1-3 short paragraphs. {lang_note}",
            text,
            max_tokens=400,
        )
        block = _append_text_block(file_id, summary)
        db.session.commit()
        target = next((f for f in files if f.id == file_id), None)
        return {
            "tool": tool,
            "action": "write",
            "result": summary,
            "target_file_id": file_id,
            "target_file_name": target.name if target else None,
            "block_id": block.id,
        }

    if tool == "smart_list":
        candidates = _all_list_candidates()
        if not candidates:
            raise ValueError("No lists found across topics")

        source_topic = topic.name
        pick = chat_json(
            "The user captured a thought in one topic and wants it added to the best "
            "matching tasks file anywhere in the system. Lists may live in other topics "
            "(e.g. grocery items → Home/Tasks, ideas → a project Tasks file). "
            'Return JSON: {"kind": "tasks_file", "file_id": number, '
            '"item_text": string, "reason": string}',
            f"Captured in topic: {source_topic}\n"
            f"Content to add:\n{text}\n\n"
            f"All task file candidates (topic → file):\n"
            f"{json.dumps(candidates, ensure_ascii=False)}",
        )
        item_text = (pick.get("item_text") or text).strip()
        file_id = int(pick["file_id"])

        task = _add_task_to_file(file_id, item_text)
        db.session.commit()
        f = File.query.get(file_id)
        target_topic = Topic.query.get(f.topic_id) if f else None
        return {
            "tool": tool,
            "action": "write",
            "result": item_text,
            "target_file_id": file_id,
            "target_file_name": f.name if f else None,
            "target_topic_id": target_topic.id if target_topic else None,
            "target_topic_name": target_topic.name if target_topic else None,
            "task_id": task.id,
            "target_kind": "task",
        }

    if tool == "create_image":
        prompt = chat_text(
            "Turn the user content into a short DALL-E image prompt (one sentence, English).",
            text,
            max_tokens=120,
        )
        image_url = generate_image(prompt)
        image_path = _save_image_from_url(image_url)

        target_file_id = context.get("file_id")
        target = None
        if target_file_id:
            target = File.query.get(int(target_file_id))
        if target is None:
            doc_candidates = [f for f in files if f.type in ("doc", "overview")]
            target = doc_candidates[0] if doc_candidates else (files[0] if files else None)
        if target is None:
            raise ValueError("No file to attach image")

        block = Block(
            file_id=target.id,
            type="image",
            content={"image_path": image_path, "filename": os.path.basename(image_path)},
            order_index=_next_order(target.id),
        )
        db.session.add(block)
        db.session.commit()
        return {
            "tool": tool,
            "action": "write",
            "result": prompt,
            "image_path": image_path,
            "target_file_id": target.id,
            "target_file_name": target.name,
            "block_id": block.id,
        }

    if tool == "create_graph":
        data_text = _data_snippets(files, blocks) or text
        spec = chat_json(
            "Create a chart spec from data. Return JSON: "
            '{"title": string, "chart_type": "bar"|"line"|"pie", '
            '"labels": string[], "values": number[], "insight": string}',
            f"Data:\n{data_text}",
        )
        data_files = [f for f in files if f.type == "data"]
        target = data_files[0] if data_files else (files[0] if files else None)
        if target is None:
            raise ValueError("No file to store chart")

        block = Block(
            file_id=target.id,
            type="table",
            content={"chart_spec": spec, "rows": []},
            order_index=_next_order(target.id),
        )
        db.session.add(block)
        db.session.commit()
        return {
            "tool": tool,
            "action": "write",
            "result": spec.get("insight", ""),
            "chart_spec": spec,
            "target_file_id": target.id,
            "target_file_name": target.name,
            "block_id": block.id,
        }

    if tool == "review":
        return {
            "tool": tool,
            "action": "stub",
            "status": "not_implemented",
            "result": "Review and analyze is coming soon.",
        }

    raise ValueError(f"Unknown tool: {tool}")
