from datetime import datetime

from flask_sqlalchemy import SQLAlchemy
from sqlalchemy.dialects.postgresql import JSONB

db = SQLAlchemy()


def _iso(dt):
    return dt.isoformat() if dt else None


class Topic(db.Model):
    __tablename__ = "topics"

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.Text, nullable=False)
    type = db.Column(db.Text, nullable=False)
    icon = db.Column(db.Text)
    color = db.Column(db.Text)
    parent_id = db.Column(db.Integer, db.ForeignKey("topics.id"))
    archived_at = db.Column(db.DateTime)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    def to_dict(self):
        return {
            "id": self.id,
            "name": self.name,
            "type": self.type,
            "icon": self.icon,
            "color": self.color,
            "parent_id": self.parent_id,
            "archived_at": _iso(self.archived_at),
            "created_at": _iso(self.created_at),
        }


class File(db.Model):
    __tablename__ = "files"

    id = db.Column(db.Integer, primary_key=True)
    topic_id = db.Column(db.Integer, db.ForeignKey("topics.id"))
    name = db.Column(db.Text, nullable=False)
    type = db.Column(db.Text, nullable=False)
    order_index = db.Column(db.Integer)
    is_main = db.Column(db.Boolean)
    archived_at = db.Column(db.DateTime)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    def to_dict(self):
        return {
            "id": self.id,
            "topic_id": self.topic_id,
            "name": self.name,
            "type": self.type,
            "order_index": self.order_index,
            "is_main": self.is_main,
            "archived_at": _iso(self.archived_at),
            "created_at": _iso(self.created_at),
        }


class Block(db.Model):
    __tablename__ = "blocks"

    id = db.Column(db.Integer, primary_key=True)
    file_id = db.Column(db.Integer, db.ForeignKey("files.id"))
    type = db.Column(db.Text, nullable=False)
    content = db.Column(JSONB, nullable=False, default=dict)
    order_index = db.Column(db.Integer)
    archived_at = db.Column(db.DateTime)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    def to_dict(self):
        return {
            "id": self.id,
            "file_id": self.file_id,
            "type": self.type,
            "content": self.content if self.content is not None else {},
            "order_index": self.order_index,
            "archived_at": _iso(self.archived_at),
            "created_at": _iso(self.created_at),
        }


class Task(db.Model):
    __tablename__ = "tasks"

    id = db.Column(db.Integer, primary_key=True)
    block_id = db.Column(db.Integer, db.ForeignKey("blocks.id"))
    title = db.Column(db.Text, nullable=False)
    status = db.Column(db.Text, default="active")
    due_date = db.Column(db.DateTime)
    archived_at = db.Column(db.DateTime)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    def to_dict(self):
        return {
            "id": self.id,
            "block_id": self.block_id,
            "title": self.title,
            "status": self.status,
            "due_date": _iso(self.due_date),
            "archived_at": _iso(self.archived_at),
            "created_at": _iso(self.created_at),
        }


class TaskView(db.Model):
    """Task membership in a view, or a section placeholder (task_id NULL)."""

    __tablename__ = "task_views"

    id = db.Column(db.Integer, primary_key=True)
    task_id = db.Column(db.Integer, db.ForeignKey("tasks.id"), nullable=True)
    view_type = db.Column(db.Text, nullable=False)
    section_name = db.Column(db.Text, nullable=True)
    order_index = db.Column(db.Integer, default=0)

    def to_dict(self):
        return {
            "id": self.id,
            "task_id": self.task_id,
            "view_type": self.view_type,
            "section_name": self.section_name,
            "order_index": self.order_index,
        }


class AutomationRule(db.Model):
    __tablename__ = "automation_rules"

    id = db.Column(db.Integer, primary_key=True)
    key = db.Column(db.Text, nullable=False, unique=True)
    name = db.Column(db.Text, nullable=False)
    action_type = db.Column(db.Text, nullable=False)
    trigger_type = db.Column(db.Text, nullable=False, default="schedule")
    schedule = db.Column(db.Text, nullable=False)
    timezone = db.Column(db.Text, nullable=False, default="UTC")
    params = db.Column(JSONB, nullable=False, default=dict)
    enabled = db.Column(db.Boolean, nullable=False, default=True)
    last_run_at = db.Column(db.DateTime)
    next_run_at = db.Column(db.DateTime)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(
        db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow
    )

    def to_dict(self):
        return {
            "id": self.id,
            "key": self.key,
            "name": self.name,
            "action_type": self.action_type,
            "trigger_type": self.trigger_type,
            "schedule": self.schedule,
            "timezone": self.timezone,
            "params": self.params if self.params is not None else {},
            "enabled": self.enabled,
            "last_run_at": _iso(self.last_run_at),
            "next_run_at": _iso(self.next_run_at),
            "created_at": _iso(self.created_at),
            "updated_at": _iso(self.updated_at),
        }


class AutomationRun(db.Model):
    __tablename__ = "automation_runs"

    id = db.Column(db.Integer, primary_key=True)
    rule_id = db.Column(db.Integer, db.ForeignKey("automation_rules.id"))
    status = db.Column(db.Text, nullable=False)
    started_at = db.Column(db.DateTime, default=datetime.utcnow)
    finished_at = db.Column(db.DateTime)
    result = db.Column(JSONB, nullable=False, default=dict)
    error = db.Column(db.Text)

    def to_dict(self):
        return {
            "id": self.id,
            "rule_id": self.rule_id,
            "status": self.status,
            "started_at": _iso(self.started_at),
            "finished_at": _iso(self.finished_at),
            "result": self.result if self.result is not None else {},
            "error": self.error,
        }


class AiProposal(db.Model):
    __tablename__ = "ai_proposals"

    id = db.Column(db.Integer, primary_key=True)
    topic_id = db.Column(db.Integer, db.ForeignKey("topics.id"))
    target_file_id = db.Column(db.Integer, db.ForeignKey("files.id"))
    proposal_type = db.Column(db.Text, nullable=False)
    payload = db.Column(JSONB, nullable=False, default=dict)
    status = db.Column(db.Text, nullable=False, default="pending")
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    decided_at = db.Column(db.DateTime)

    def to_dict(self):
        return {
            "id": self.id,
            "topic_id": self.topic_id,
            "target_file_id": self.target_file_id,
            "proposal_type": self.proposal_type,
            "payload": self.payload if self.payload is not None else {},
            "status": self.status,
            "created_at": _iso(self.created_at),
            "decided_at": _iso(self.decided_at),
        }
