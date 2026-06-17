from datetime import datetime

from flask import Blueprint, jsonify, request

from models import AiProposal, Block, db
from routes.helpers import get_or_404
from services.ai_proposal_actions import finalize_process_update

ai_proposals_bp = Blueprint("ai_proposals", __name__)


@ai_proposals_bp.route("/ai_proposals", methods=["GET"])
def list_ai_proposals():
    query = AiProposal.query
    status = request.args.get("status")
    topic_id = request.args.get("topic_id")
    target_file_id = request.args.get("target_file_id")
    if status:
        query = query.filter_by(status=status)
    if topic_id:
        query = query.filter_by(topic_id=int(topic_id))
    if target_file_id:
        query = query.filter_by(target_file_id=int(target_file_id))
    proposals = query.order_by(AiProposal.created_at.desc(), AiProposal.id.desc()).all()
    return jsonify([p.to_dict() for p in proposals])


@ai_proposals_bp.route("/ai_proposals/<int:proposal_id>", methods=["GET"])
def get_ai_proposal(proposal_id):
    return jsonify(get_or_404(AiProposal, proposal_id).to_dict())


@ai_proposals_bp.route("/ai_proposals", methods=["POST"])
def create_ai_proposal():
    data = request.get_json(silent=True) or {}
    if not data.get("proposal_type"):
        return jsonify({"error": "proposal_type is required"}), 400
    proposal = AiProposal(
        topic_id=data.get("topic_id"),
        target_file_id=data.get("target_file_id"),
        proposal_type=data["proposal_type"],
        payload=data.get("payload", {}),
        status=data.get("status", "pending"),
    )
    db.session.add(proposal)
    db.session.commit()
    return jsonify(proposal.to_dict()), 201


@ai_proposals_bp.route("/ai_proposals/<int:proposal_id>/approve", methods=["POST"])
def approve_ai_proposal(proposal_id):
    proposal = get_or_404(AiProposal, proposal_id)
    if proposal.status != "pending":
        return jsonify({"error": "proposal is already decided"}), 400
    if proposal.proposal_type == "process_smart_update":
        return jsonify(
            {"error": "use /ai_proposals/<id>/finalize for process smart updates"}
        ), 400
    if proposal.proposal_type == "process_refresh_skipped":
        proposal.status = "rejected"
        proposal.decided_at = datetime.utcnow()
        db.session.commit()
        return jsonify(proposal.to_dict())

    payload = proposal.payload or {}
    block_type = payload.get("block_type")
    content = payload.get("content")
    if proposal.target_file_id and block_type and isinstance(content, dict):
        block = Block(
            file_id=proposal.target_file_id,
            type=block_type,
            content=content,
            order_index=_next_block_order(proposal.target_file_id),
        )
        db.session.add(block)

    proposal.status = "approved"
    proposal.decided_at = datetime.utcnow()
    db.session.commit()
    return jsonify(proposal.to_dict())


@ai_proposals_bp.route("/ai_proposals/<int:proposal_id>/finalize", methods=["POST"])
def finalize_ai_proposal(proposal_id):
    proposal = get_or_404(AiProposal, proposal_id)
    data = request.get_json(silent=True) or {}
    try:
        proposal = finalize_process_update(proposal, data.get("decisions") or {})
        db.session.commit()
        return jsonify(proposal.to_dict())
    except ValueError as error:
        db.session.rollback()
        return jsonify({"error": str(error)}), 400


@ai_proposals_bp.route("/ai_proposals/<int:proposal_id>/reject", methods=["POST"])
def reject_ai_proposal(proposal_id):
    proposal = get_or_404(AiProposal, proposal_id)
    if proposal.status != "pending":
        return jsonify({"error": "proposal is already decided"}), 400
    proposal.status = "rejected"
    proposal.decided_at = datetime.utcnow()
    db.session.commit()
    return jsonify(proposal.to_dict())


def _next_block_order(file_id):
    last = (
        Block.query.filter_by(file_id=file_id)
        .order_by(Block.order_index.desc(), Block.id.desc())
        .first()
    )
    if last is None or last.order_index is None:
        return 0
    return last.order_index + 1
