import json

from models import AiProposal, Block, File, db
from services.openai_service import chat_text


def create_process_refresh_proposal(topic, old_file, new_file, proposal_type):
    context = _file_text(old_file.id)
    prompt = (
        "Suggest practical updates for the refreshed process file. "
        "Keep the response concise and directly usable."
    )
    if proposal_type == "tasks_refresh":
        prompt = (
            "Suggest an updated task list for this process. "
            "Return short actionable items, one per line."
        )

    suggestion = chat_text(
        prompt,
        f"Topic: {topic.name}\nOld file: {old_file.name}\nContent:\n{context}",
        max_tokens=500,
    )
    block_type = "text"
    content = {"text": suggestion}

    proposal = AiProposal(
        topic_id=topic.id,
        target_file_id=new_file.id,
        proposal_type=proposal_type,
        payload={
            "source_file_id": old_file.id,
            "source_file_name": old_file.name,
            "target_file_name": new_file.name,
            "block_type": block_type,
            "content": content,
        },
    )
    db.session.add(proposal)
    db.session.flush()
    return proposal


def _file_text(file_id):
    blocks = (
        Block.query.filter_by(file_id=file_id)
        .order_by(Block.order_index, Block.id)
        .all()
    )
    parts = []
    for block in blocks:
        content = block.content or {}
        if block.type in ("text", "summary", "header"):
            text = content.get("text")
            if text:
                parts.append(str(text))
        elif block.type in ("table", "list", "task_list"):
            parts.append(json.dumps(content, ensure_ascii=False))
    return "\n".join(parts)[:8000]
