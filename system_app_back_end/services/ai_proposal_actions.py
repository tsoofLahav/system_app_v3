from models import AiProposal, db
from services.ai_smart_update.finalize_process import finalize_process_update
from services.ai_smart_update.finalize_project import finalize_project_update
from services.ai_smart_update.process_update import smart_process_update
from services.ai_smart_update.project_update import smart_project_update


def create_smart_process_update_proposal(topic, plan_file, doc_file, tasks_file):
    payload = smart_process_update(topic, plan_file, doc_file, tasks_file)
    proposal = AiProposal(
        topic_id=topic.id,
        target_file_id=None,
        proposal_type="process_smart_update",
        payload=payload,
        status="pending",
    )
    db.session.add(proposal)
    db.session.flush()
    return proposal


def create_smart_project_update_proposal(
    topic, log_file, plan_file, execution_file, tasks_file, doc_file
):
    payload = smart_project_update(
        topic, log_file, plan_file, execution_file, tasks_file, doc_file
    )
    proposal = AiProposal(
        topic_id=topic.id,
        target_file_id=None,
        proposal_type="project_smart_update",
        payload=payload,
        status="pending",
    )
    db.session.add(proposal)
    db.session.flush()
    return proposal


def create_process_refresh_skipped_proposal(topic, missing_types, message):
    proposal = AiProposal(
        topic_id=topic.id,
        target_file_id=None,
        proposal_type="process_refresh_skipped",
        payload={
            "missing_types": missing_types,
            "message": message,
        },
        status="pending",
    )
    db.session.add(proposal)
    db.session.flush()
    return proposal


def create_project_update_skipped_proposal(topic, message, missing_types=None):
    proposal = AiProposal(
        topic_id=topic.id,
        target_file_id=None,
        proposal_type="project_update_skipped",
        payload={
            "missing_types": missing_types or [],
            "message": message,
        },
        status="pending",
    )
    db.session.add(proposal)
    db.session.flush()
    return proposal
