import json
import os
import uuid
from urllib.request import urlopen

from flask import current_app

from models import Block, File, Topic, db
from services.ai_interactive.smart_doc import run_smart_doc
from services.ai_interactive.smart_list import run_smart_list
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


def _save_image_bytes(data: bytes) -> str:
    upload_folder = current_app.config["UPLOAD_FOLDER"]
    os.makedirs(upload_folder, exist_ok=True)
    filename = f"ai_{uuid.uuid4().hex[:10]}.png"
    path = os.path.join(upload_folder, filename)
    with open(path, "wb") as out:
        out.write(data)
    return f"/images/{filename}"


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
        return run_smart_doc(text=text, source_topic_id=topic_id, locale=locale)

    if tool == "smart_list":
        return run_smart_list(text=text, source_topic_id=topic_id, locale=locale)

    if tool == "create_image":
        prompt = chat_text(
            "Turn the user content into a short image-generation prompt "
            "(one sentence, English).",
            text,
            max_tokens=120,
        )
        image_bytes = generate_image(prompt)
        image_path = _save_image_bytes(image_bytes)

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
