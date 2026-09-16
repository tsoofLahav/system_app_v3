"""Review ownership and acknowledgements, stored on the existing run JSON."""
from models import db, Automation, AutomationRun, AgentPendingReview, File, Topic, Task


def pending_for_run(run):
    refs = (run.result or {}).get('review_refs')
    if refs is not None:
        pairs = {(r['id'], r['run_key']) for r in refs}
    else:
        # Previous releases already saved conversation IDs alongside review IDs.
        ids, keys = set(), set()
        def visit(value):
            if isinstance(value, dict):
                ids.update(value.get('pending_review_ids') or [])
                if value.get('conversation_id'):
                    keys.add(value['conversation_id'])
                for child in value.values():
                    visit(child)
            elif isinstance(value, list):
                for child in value:
                    visit(child)
        visit(run.result or {})
        if not ids or not keys:
            return []  # Unknown legacy ownership is never guessed for deletion.
        pairs = {(rid, key) for rid in ids for key in keys}
    if not pairs:
        return []
    automation = db.session.get(Automation, run.automation_id)
    rows = AgentPendingReview.query.filter(
        AgentPendingReview.id.in_([rid for rid, _ in pairs]),
        AgentPendingReview.workspace_id == automation.workspace_id,
    ).all()
    return [row for row in rows if (row.id, row.run_key) in pairs]


def capture_review_refs(result):
    ids = [rid for step in result.get('steps', []) for rid in step.get('pending_review_ids', [])]
    rows = AgentPendingReview.query.filter(AgentPendingReview.id.in_(ids)).all() if ids else []
    return [{"id": row.id, "run_key": row.run_key, "topic_id": row.topic_id, "file_id": row.file_id}
            for row in rows]


def dismiss_task_reviews(task):
    if getattr(task, 'complimentary_role', None) != 'review' or not task.source_automation_id:
        return
    for run in AutomationRun.query.filter_by(automation_id=task.source_automation_id).all():
        for row in pending_for_run(run):
            db.session.delete(row)
        run.event_context = {**(run.event_context or {}), 'review_dismissed': True}


def topic_review_state(topic):
    files = File.query.filter_by(topic_id=topic.id).filter(File.archived_at.is_(None)).all()
    pending = AgentPendingReview.query.filter_by(topic_id=topic.id, workspace_id=topic.workspace_id).all()
    pending_ids = {p.file_id for p in pending}
    runs = []
    for run in (AutomationRun.query.join(Automation, Automation.id == AutomationRun.automation_id)
                .filter(Automation.workspace_id == topic.workspace_id, AutomationRun.status == 'completed').all()):
        context = run.event_context or {}
        if context.get('review_dismissed') or topic.id in context.get('reviewed_topic_ids', []):
            continue
        topic_ids = context.get('review_topic_ids')
        if topic_ids is None:
            topic_ids = [p.topic_id for p in pending_for_run(run)]
        task = Task.query.filter_by(source_automation_id=run.automation_id, complimentary_role='review').first()
        if topic.id in topic_ids and task is not None and task.status == 'active':
            runs.append(run.id)
    return {'topic': {'id': topic.id, 'name': topic.name, 'color': topic.color},
            'files': [{'id': f.id, 'name': f.name} for f in files if f.id in pending_ids],
            'run_ids': runs}


def acknowledge_topic(topic, run_ids):
    from .section_windows import complete_review_if_clear, input_topics
    for run_id in run_ids:
        run = db.session.get(AutomationRun, int(run_id))
        if run is None:
            continue
        automation = db.session.get(Automation, run.automation_id)
        if automation.workspace_id != topic.workspace_id or run.status != 'completed':
            continue
        context = dict(run.event_context or {})
        if context.get('review_dismissed'):
            continue
        allowed = context.get('review_topic_ids')
        if allowed is None:
            allowed = [t['id'] for t in input_topics(automation)]
            context['review_topic_ids'] = allowed
        if topic.id not in allowed:
            continue
        if any(row.topic_id == topic.id for row in pending_for_run(run)):
            continue
        context['reviewed_topic_ids'] = sorted(set(context.get('reviewed_topic_ids', [])) | {topic.id})
        run.event_context = context
        db.session.flush()
        complete_review_if_clear(automation)
