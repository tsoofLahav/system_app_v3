"""Create a graph block from captured text."""

from __future__ import annotations

from models import Block, File, db
from services.ai_interactive.graph_content import parse_graph_ai_result
from services.openai_service import chat_json


def _topic_files(topic_id: int) -> list[File]:
    return (
        File.query.filter_by(topic_id=int(topic_id))
        .filter(File.archived_at.is_(None))
        .order_by(File.order_index, File.id)
        .all()
    )


def _active_blocks(file_id: int) -> list[Block]:
    return (
        Block.query.filter_by(file_id=file_id)
        .filter(Block.archived_at.is_(None))
        .order_by(Block.order_index, Block.id)
        .all()
    )


def _next_order(file_id: int) -> int:
    last = (
        Block.query.filter_by(file_id=file_id)
        .order_by(Block.order_index.desc(), Block.id.desc())
        .first()
    )
    if last is None or last.order_index is None:
        return 0
    return last.order_index + 1


def _resolve_target_file(files: list[File], context: dict) -> File:
    file_id = context.get("file_id")
    if file_id is not None:
        matched = next((f for f in files if f.id == int(file_id)), None)
        if matched is not None:
            return matched

    for file_type in ("doc", "overview", "data"):
        candidates = [f for f in files if f.type == file_type]
        if candidates:
            return candidates[0]

    if not files:
        raise ValueError("No file available to store the graph")
    return files[0]


def _insert_graph_block(
    *,
    file_id: int,
    content: dict,
    after_block_id: int | None = None,
) -> Block:
    blocks = _active_blocks(file_id)
    insert_order = _next_order(file_id)

    if after_block_id is not None:
        anchor = next((block for block in blocks if block.id == int(after_block_id)), None)
        if anchor is not None:
            insert_order = (anchor.order_index or 0) + 1
            for block in blocks:
                if (block.order_index or 0) >= insert_order:
                    block.order_index = (block.order_index or 0) + 1

    graph_block = Block(
        file_id=file_id,
        type="graph",
        content=content,
        order_index=insert_order,
    )
    db.session.add(graph_block)
    db.session.flush()
    return graph_block


def run_create_graph(
    *,
    text: str,
    topic_id: int,
    context: dict,
    locale: str = "en",
) -> dict:
    cleaned = text.strip()
    if not cleaned:
        raise ValueError("No context text provided")

    lang_note = "Respond in Hebrew." if locale == "he" else "Respond in English."
    ai_result = chat_json(
        "The user selected text and wants it turned into chart data for a simple graph "
        "block with labels and numeric values. "
        "If the text is prose, a single fact, an instruction, or otherwise not comparable "
        "numeric data, set can_graph to false and explain briefly in message. "
        "If it can be graphed, extract a short title, chart_type, parallel labels and "
        "values from the text. Prefer bar charts for categories, line for trends over time, "
        "pie for parts of a whole. "
        f'{lang_note} Return JSON: {{"can_graph": boolean, "message": string, '
        '"title": string, "chart_type": "bar"|"line"|"pie", '
        '"labels": string[], "values": number[]}}',
        f"Text:\n{cleaned}",
    )

    can_graph, message, graph_content = parse_graph_ai_result(ai_result)
    if not can_graph:
        return {
            "tool": "create_graph",
            "action": "display",
            "status": "not_graphable",
            "result": message,
        }

    files = _topic_files(topic_id)
    target = _resolve_target_file(files, context)
    after_block_id = context.get("block_id")
    if after_block_id is not None and int(context.get("file_id") or 0) != target.id:
        after_block_id = None

    graph_block = _insert_graph_block(
        file_id=target.id,
        content=graph_content,
        after_block_id=int(after_block_id) if after_block_id is not None else None,
    )
    db.session.commit()

    return {
        "tool": "create_graph",
        "action": "write",
        "result": message,
        "target_file_id": target.id,
        "target_file_name": target.name,
        "block_id": graph_block.id,
        "chart_type": graph_content["chart_type"],
        "point_count": len(graph_content["labels"]),
    }
