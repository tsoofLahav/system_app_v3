from flask import Blueprint, jsonify, request

from models import Block, db
from routes.helpers import active_query, apply_updates, get_or_404

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
    )
    db.session.add(block)
    db.session.commit()
    return jsonify(block.to_dict()), 201


@blocks_bp.route("/blocks/<int:block_id>", methods=["PATCH"])
def update_block(block_id):
    block = get_or_404(Block, block_id)
    data = request.get_json(silent=True) or {}
    apply_updates(
        block,
        data,
        {"file_id", "type", "content", "order_index", "archived_at"},
        datetime_fields={"archived_at"},
    )
    db.session.commit()
    return jsonify(block.to_dict())


@blocks_bp.route("/blocks/<int:block_id>", methods=["DELETE"])
def delete_block(block_id):
    block = get_or_404(Block, block_id)
    db.session.delete(block)
    db.session.commit()
    return "", 204
