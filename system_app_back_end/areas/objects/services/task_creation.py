"""Idempotent task allocation; retries return the original task."""
from sqlalchemy.exc import IntegrityError
from models import Task, db


def allocate_task(task, data, scope):
    key = data.get("creation_key")
    if key is not None and (not isinstance(key, str) or not 1 <= len(key) <= 160):
        raise ValueError("invalid creation key")
    task.creation_key = f"{scope}:{key}" if key else None
    if task.creation_key:
        existing = Task.query.filter_by(creation_key=task.creation_key).first()
        if existing:
            return existing, True
    try:
        with db.session.begin_nested():
            db.session.add(task)
            db.session.flush()
    except IntegrityError:
        if not task.creation_key:
            raise
        existing = Task.query.filter_by(creation_key=task.creation_key).first()
        if existing is None:
            raise
        return existing, True
    return task, False
