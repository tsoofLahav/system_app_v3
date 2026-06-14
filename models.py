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
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    def to_dict(self):
        return {
            "id": self.id,
            "name": self.name,
            "type": self.type,
            "icon": self.icon,
            "color": self.color,
            "parent_id": self.parent_id,
            "created_at": _iso(self.created_at),
        }


class File(db.Model):
    __tablename__ = "files"

    id = db.Column(db.Integer, primary_key=True)
    topic_id = db.Column(db.Integer, db.ForeignKey("topics.id"))
    name = db.Column(db.Text, nullable=False)
    type = db.Column(db.Text, nullable=False)
    order_index = db.Column(db.Integer)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    def to_dict(self):
        return {
            "id": self.id,
            "topic_id": self.topic_id,
            "name": self.name,
            "type": self.type,
            "order_index": self.order_index,
            "created_at": _iso(self.created_at),
        }


class Block(db.Model):
    __tablename__ = "blocks"

    id = db.Column(db.Integer, primary_key=True)
    file_id = db.Column(db.Integer, db.ForeignKey("files.id"))
    type = db.Column(db.Text, nullable=False)
    content = db.Column(JSONB, nullable=False, default=dict)
    order_index = db.Column(db.Integer)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    def to_dict(self):
        return {
            "id": self.id,
            "file_id": self.file_id,
            "type": self.type,
            "content": self.content if self.content is not None else {},
            "order_index": self.order_index,
            "created_at": _iso(self.created_at),
        }


class Task(db.Model):
    __tablename__ = "tasks"

    id = db.Column(db.Integer, primary_key=True)
    block_id = db.Column(db.Integer, db.ForeignKey("blocks.id"))
    title = db.Column(db.Text, nullable=False)
    status = db.Column(db.Text, default="active")
    due_date = db.Column(db.DateTime)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    def to_dict(self):
        return {
            "id": self.id,
            "block_id": self.block_id,
            "title": self.title,
            "status": self.status,
            "due_date": _iso(self.due_date),
            "created_at": _iso(self.created_at),
        }


class TaskView(db.Model):
    """Task membership in a view, or a section placeholder (task_id NULL)."""

    __tablename__ = "task_views"

    id = db.Column(db.Integer, primary_key=True)
    task_id = db.Column(db.Integer, db.ForeignKey("tasks.id"), nullable=True)
    view_type = db.Column(db.Text, nullable=False)
    section_name = db.Column(db.Text, nullable=True)

    def to_dict(self):
        return {
            "id": self.id,
            "task_id": self.task_id,
            "view_type": self.view_type,
            "section_name": self.section_name,
        }
