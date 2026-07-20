from flask import Blueprint, jsonify, request

from models import Block, File, db
from routes.helpers import active_query, apply_updates, get_or_404
from services.automation_dispatcher import dispatch_file_changed


def _topic_id_for_file(file_id):
    if file_id is None:
        return None
    file = db.session.get(File, file_id)
    return file.topic_id if file is not None else None

blocks_bp = Blueprint("blocks", __name__)


@blocks_bp.route("/blocks", methods=["GET"])
def list_blocks():
    blocks = active_query(Block).order_by(Block.order_index, Block.id).all()
    return jsonify([b.to_dict() for b in blocks])


@blocks_bp.route("/blocks/<int:block_id>", methods=["GET"])
def get_block(block_id):
    return jsonify(get_or_404(Block, block_id).to_dict())


@blocks_bp.route("/files/<int:file_id>/blocks", methods=["GET"])
def list_blocks_by_file(file_id):
    blocks = (
        active_query(Block)
        .filter_by(file_id=file_id)
        .order_by(Block.order_index, Block.id)
        .all()
    )
    return jsonify([b.to_dict() for b in blocks])


@blocks_bp.route("/blocks", methods=["POST"])
def create_block():
    data = request.get_json(silent=True) or {}
    if not data.get("type"):
        return jsonify({"error": "type is required"}), 400

    block = Block(
        file_id=data.get("file_id"),
        type=data["type"],
        content=data.get("content", {}),
        order_index=data.get("order_index"),
        part_id=data.get("part_id"),
    )
    db.session.add(block)
    db.session.commit()
    dispatch_file_changed(block.file_id, "block_created", {"block_id": block.id})
    return jsonify(block.to_dict()), 201


@blocks_bp.route("/files/<int:file_id>/blocks/reorder", methods=["POST"])
def reorder_blocks(file_id):
    get_or_404(File, file_id)
    data = request.get_json(silent=True) or {}
    updates = data.get("updates")
    if not isinstance(updates, list) or not updates:
        return jsonify({"error": "updates must be a non-empty list"}), 400

    block_ids = []
    order_by_id = {}
    for item in updates:
        if not isinstance(item, dict):
            return jsonify({"error": "each update must be an object"}), 400
        block_id = item.get("id")
        order_index = item.get("order_index")
        if block_id is None or order_index is None:
            return jsonify({"error": "each update requires id and order_index"}), 400
        block_ids.append(int(block_id))
        order_by_id[int(block_id)] = int(order_index)

    blocks = (
        active_query(Block)
        .filter(Block.id.in_(block_ids), Block.file_id == file_id)
        .all()
    )
    if len(blocks) != len(set(block_ids)):
        return jsonify({"error": "invalid block ids for file"}), 400

    for block in blocks:
        block.order_index = order_by_id[block.id]

    db.session.commit()
    dispatch_file_changed(file_id, "blocks_reordered")
    return jsonify({"updated": len(blocks)})


@blocks_bp.route("/blocks/<int:block_id>", methods=["PATCH"])
def update_block(block_id):
    block = get_or_404(Block, block_id)
    data = request.get_json(silent=True) or {}
    apply_updates(
        block,
        data,
        {"file_id", "type", "content", "order_index", "part_id", "archived_at"},
        datetime_fields={"archived_at"},
    )
    db.session.commit()
    dispatch_file_changed(block.file_id, "block_updated", {"block_id": block.id})
    return jsonify(block.to_dict())


@blocks_bp.route("/blocks/<int:block_id>", methods=["DELETE"])
def delete_block(block_id):
    block = get_or_404(Block, block_id)
    file_id = block.file_id
    db.session.delete(block)
    db.session.commit()
    dispatch_file_changed(file_id, "block_deleted", {"block_id": block_id})
    return "", 204
