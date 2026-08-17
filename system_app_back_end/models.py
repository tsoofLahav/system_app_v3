from datetime import datetime

from flask_sqlalchemy import SQLAlchemy
from sqlalchemy.dialects.postgresql import JSONB

from shared.run_config import DEFAULT_AUTOMATION_APPLY_MODE

db = SQLAlchemy()


def _iso(dt):
    return dt.isoformat() if dt else None


class Workspace(db.Model):
    __tablename__ = "workspaces"

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.Text, nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    def to_dict(self):
        return {
            "id": self.id,
            "name": self.name,
            "created_at": _iso(self.created_at),
        }


class Topic(db.Model):
    __tablename__ = "topics"

    id = db.Column(db.Integer, primary_key=True)
    workspace_id = db.Column(db.Integer, db.ForeignKey("workspaces.id"), nullable=False)
    name = db.Column(db.Text, nullable=False)
    icon = db.Column(db.Text)
    color = db.Column(db.Text)
    order_index = db.Column(db.Integer, nullable=False, default=0)
    file_layout = db.Column(db.Text, nullable=False, default="single")
    archived_at = db.Column(db.DateTime)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    def to_dict(self):
        return {
            "id": self.id,
            "workspace_id": self.workspace_id,
            "name": self.name,
            "icon": self.icon,
            "color": self.color,
            "order_index": self.order_index,
            "file_layout": self.file_layout or "single",
            "archived_at": _iso(self.archived_at),
            "created_at": _iso(self.created_at),
        }


class File(db.Model):
    __tablename__ = "files"

    id = db.Column(db.Integer, primary_key=True)
    topic_id = db.Column(db.Integer, db.ForeignKey("topics.id"), nullable=False)
    name = db.Column(db.Text, nullable=False)
    document_json = db.Column(db.Text, nullable=False, default="")
    order_index = db.Column(db.Integer, nullable=False, default=0)
    meta = db.Column(JSONB, nullable=False, default=dict)
    archived_at = db.Column(db.DateTime)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    def to_dict(self, *, include_document: bool = True):
        data = {
            "id": self.id,
            "topic_id": self.topic_id,
            "name": self.name,
            "order_index": self.order_index,
            "meta": self.meta if self.meta is not None else {},
            "archived_at": _iso(self.archived_at),
            "created_at": _iso(self.created_at),
        }
        if include_document:
            # Serve editor text (v4). Legacy v3 JSON is migrated in the response
            # (spans dropped); next save persists the text form.
            from areas.files.services.document_marker_text import (
                ensure_editor_text,
                is_editor_text,
            )

            raw = self.document_json or ""
            data["document_json"] = (
                raw if is_editor_text(raw) else ensure_editor_text(raw)
            )
        return data


class TaskList(db.Model):
    __tablename__ = "task_lists"

    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.Text, nullable=False, default="")
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    def to_dict(self):
        return {
            "id": self.id,
            "title": self.title or "",
            "created_at": _iso(self.created_at),
        }


class Task(db.Model):
    __tablename__ = "tasks"

    id = db.Column(db.Integer, primary_key=True)
    task_list_id = db.Column(db.Integer, db.ForeignKey("task_lists.id"))
    title = db.Column(db.Text, nullable=False)
    status = db.Column(db.Text, nullable=False, default="active")
    due_date = db.Column(db.DateTime)
    list_order_index = db.Column(db.Integer, nullable=False, default=0)
    archived_at = db.Column(db.DateTime)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    def to_dict(self):
        return {
            "id": self.id,
            "task_list_id": self.task_list_id,
            "title": self.title,
            "status": self.status,
            "due_date": _iso(self.due_date),
            "list_order_index": self.list_order_index,
            "archived_at": _iso(self.archived_at),
            "created_at": _iso(self.created_at),
        }


class InformationPiece(db.Model):
    __tablename__ = "information_pieces"

    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.Text, nullable=False, default="")
    body = db.Column(db.Text, nullable=False, default="")
    metadata_ = db.Column("metadata", JSONB, nullable=False, default=dict)
    archived_at = db.Column(db.DateTime)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    def to_dict(self):
        return {
            "id": self.id,
            "title": self.title,
            "body": self.body or "",
            "metadata": self.metadata_ if self.metadata_ is not None else {},
            "archived_at": _iso(self.archived_at),
            "created_at": _iso(self.created_at),
        }


class ObjectEmbed(db.Model):
    __tablename__ = "objects"

    id = db.Column(db.Integer, primary_key=True)
    file_id = db.Column(db.Integer, db.ForeignKey("files.id"), nullable=False)
    type = db.Column(db.Text, nullable=False)
    task_list_id = db.Column(db.Integer, db.ForeignKey("task_lists.id"))
    information_id = db.Column(db.Integer, db.ForeignKey("information_pieces.id"))
    payload = db.Column(JSONB, nullable=False, default=dict)
    anchor = db.Column(JSONB, nullable=False, default=dict)
    sort_key = db.Column(db.Integer, nullable=False, default=0)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    def to_dict(self, *, task_list=None, tasks=None, information=None):
        data = {
            "id": self.id,
            "file_id": self.file_id,
            "type": self.type,
            "task_list_id": self.task_list_id,
            "information_id": self.information_id,
            "payload": self.payload if self.payload is not None else {},
            "anchor": self.anchor if self.anchor is not None else {},
            "sort_key": self.sort_key,
            "created_at": _iso(self.created_at),
        }
        if task_list is not None:
            data["task_list"] = (
                task_list if isinstance(task_list, dict) else task_list.to_dict()
            )
        if tasks is not None:
            data["tasks"] = [
                t if isinstance(t, dict) else t.to_dict() for t in tasks
            ]
        if information is not None:
            data["information"] = (
                information
                if isinstance(information, dict)
                else information.to_dict()
            )
        return data


class Tag(db.Model):
    __tablename__ = "tags"

    id = db.Column(db.Integer, primary_key=True)
    workspace_id = db.Column(db.Integer, db.ForeignKey("workspaces.id"), nullable=False)
    name = db.Column(db.Text, nullable=False)
    color = db.Column(db.Text)
    icon = db.Column(db.Text)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    def to_dict(self):
        return {
            "id": self.id,
            "workspace_id": self.workspace_id,
            "name": self.name,
            "color": self.color,
            "icon": self.icon,
            "created_at": _iso(self.created_at),
        }


class EntityTag(db.Model):
    __tablename__ = "entity_tags"

    id = db.Column(db.Integer, primary_key=True)
    tag_id = db.Column(db.Integer, db.ForeignKey("tags.id"), nullable=False)
    entity_type = db.Column(db.Text, nullable=False)
    entity_id = db.Column(db.Integer, nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    def to_dict(self):
        return {
            "id": self.id,
            "tag_id": self.tag_id,
            "entity_type": self.entity_type,
            "entity_id": self.entity_id,
            "created_at": _iso(self.created_at),
        }


class Link(db.Model):
    __tablename__ = "links"

    id = db.Column(db.Integer, primary_key=True)
    workspace_id = db.Column(db.Integer, db.ForeignKey("workspaces.id"), nullable=False)
    source_type = db.Column(db.Text, nullable=False)
    source_id = db.Column(db.Integer, nullable=False)
    target_type = db.Column(db.Text, nullable=False)
    target_id = db.Column(db.Integer, nullable=False)
    kind = db.Column(db.Text, nullable=False, default="related")
    anchor = db.Column(JSONB)
    label = db.Column(db.Text)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    def to_dict(self):
        return {
            "id": self.id,
            "workspace_id": self.workspace_id,
            "source_type": self.source_type,
            "source_id": self.source_id,
            "target_type": self.target_type,
            "target_id": self.target_id,
            "kind": self.kind or "related",
            "anchor": self.anchor if self.anchor is not None else None,
            "label": self.label,
            "created_at": _iso(self.created_at),
        }


class View(db.Model):
    __tablename__ = "views"

    id = db.Column(db.Integer, primary_key=True)
    workspace_id = db.Column(db.Integer, db.ForeignKey("workspaces.id"), nullable=False)
    name = db.Column(db.Text, nullable=False)
    layout_config = db.Column(JSONB, nullable=False, default=dict)
    order_index = db.Column(db.Integer, nullable=False, default=0)
    archived_at = db.Column(db.DateTime)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    def to_dict(self):
        return {
            "id": self.id,
            "workspace_id": self.workspace_id,
            "name": self.name,
            "layout_config": self.layout_config if self.layout_config is not None else {},
            "order_index": self.order_index,
            "archived_at": _iso(self.archived_at),
            "created_at": _iso(self.created_at),
        }


class ViewTaskMembership(db.Model):
    __tablename__ = "view_task_memberships"

    id = db.Column(db.Integer, primary_key=True)
    view_id = db.Column(db.Integer, db.ForeignKey("views.id"), nullable=False)
    task_id = db.Column(db.Integer, db.ForeignKey("tasks.id"))
    section_name = db.Column(db.Text)
    order_index = db.Column(db.Integer, nullable=False, default=0)
    section_flag = db.Column(db.Text)
    topic_key = db.Column(db.Text)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    def to_dict(self):
        return {
            "id": self.id,
            "view_id": self.view_id,
            "task_id": self.task_id,
            "section_name": self.section_name,
            "order_index": self.order_index,
            "section_flag": self.section_flag,
            "topic_key": self.topic_key,
            "created_at": _iso(self.created_at),
        }


class Automation(db.Model):
    __tablename__ = "automations"

    id = db.Column(db.Integer, primary_key=True)
    workspace_id = db.Column(db.Integer, db.ForeignKey("workspaces.id"), nullable=False)
    name = db.Column(db.Text, nullable=False)
    trigger = db.Column(JSONB, nullable=False, default=dict)
    scope = db.Column(JSONB, nullable=False, default=dict)
    prompt = db.Column(db.Text, nullable=False, default="")
    apply_mode = db.Column(
        db.Text, nullable=False, default=DEFAULT_AUTOMATION_APPLY_MODE
    )
    schedule = db.Column(db.Text)
    timezone = db.Column(db.Text, nullable=False, default="UTC")
    enabled = db.Column(db.Boolean, nullable=False, default=True)
    # A saved action is an automation with no schedule: `icon` and `bar_slot`
    # are how it shows up in the app (slot 1..6 = on the AI bar, NULL = menu).
    icon = db.Column(db.Text, nullable=False, default="")
    bar_slot = db.Column(db.Integer)
    last_run_at = db.Column(db.DateTime)
    next_run_at = db.Column(db.DateTime)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(
        db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow
    )

    def to_dict(self):
        return {
            "id": self.id,
            "workspace_id": self.workspace_id,
            "name": self.name,
            "trigger": self.trigger if self.trigger is not None else {},
            "scope": self.scope if self.scope is not None else {},
            "prompt": self.prompt or "",
            "apply_mode": self.apply_mode,
            "icon": self.icon or "",
            "bar_slot": self.bar_slot,
            "schedule": self.schedule,
            "timezone": self.timezone,
            "enabled": self.enabled,
            "last_run_at": _iso(self.last_run_at),
            "next_run_at": _iso(self.next_run_at),
            "created_at": _iso(self.created_at),
            "updated_at": _iso(self.updated_at),
        }


class AutomationRun(db.Model):
    __tablename__ = "automation_runs"

    id = db.Column(db.Integer, primary_key=True)
    automation_id = db.Column(db.Integer, db.ForeignKey("automations.id"), nullable=False)
    status = db.Column(db.Text, nullable=False)
    trigger_source = db.Column(db.Text, nullable=False, default="schedule")
    event_context = db.Column(JSONB, nullable=False, default=dict)
    started_at = db.Column(db.DateTime, default=datetime.utcnow)
    finished_at = db.Column(db.DateTime)
    result = db.Column(JSONB, nullable=False, default=dict)
    error = db.Column(db.Text)

    def to_dict(self):
        return {
            "id": self.id,
            "automation_id": self.automation_id,
            "status": self.status,
            "trigger_source": self.trigger_source,
            "event_context": self.event_context if self.event_context is not None else {},
            "started_at": _iso(self.started_at),
            "finished_at": _iso(self.finished_at),
            "result": self.result if self.result is not None else {},
            "error": self.error,
        }


class FileVersion(db.Model):
    __tablename__ = "file_versions"

    id = db.Column(db.Integer, primary_key=True)
    file_id = db.Column(db.Integer, db.ForeignKey("files.id"), nullable=False)
    body = db.Column(db.Text, nullable=False)
    source = db.Column(db.Text, nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    def to_dict(self):
        return {
            "id": self.id,
            "file_id": self.file_id,
            "body": self.body,
            "source": self.source,
            "created_at": _iso(self.created_at),
        }


class AgentConfig(db.Model):
    __tablename__ = "agent_configs"

    id = db.Column(db.Integer, primary_key=True)
    workspace_id = db.Column(db.Integer, db.ForeignKey("workspaces.id"), nullable=False)
    name = db.Column(db.Text, nullable=False, default="default")
    # Empty means "whatever the deployment runs" (config.OPENAI_MODEL). A value
    # here is a deliberate per-workspace override and outranks the environment.
    model = db.Column(db.Text, nullable=False, default="")
    system_prompt = db.Column(db.Text, nullable=False, default="")
    tool_allowlist = db.Column(JSONB, nullable=False, default=list)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(
        db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow
    )

    def to_dict(self):
        return {
            "id": self.id,
            "workspace_id": self.workspace_id,
            "name": self.name,
            "model": self.model,
            "system_prompt": self.system_prompt or "",
            "tool_allowlist": self.tool_allowlist if self.tool_allowlist is not None else [],
            "created_at": _iso(self.created_at),
            "updated_at": _iso(self.updated_at),
        }


class AgentPendingReview(db.Model):
    __tablename__ = "agent_pending_reviews"

    id = db.Column(db.Integer, primary_key=True)
    workspace_id = db.Column(db.Integer, db.ForeignKey("workspaces.id"), nullable=False)
    topic_id = db.Column(db.Integer, db.ForeignKey("topics.id"), nullable=False)
    file_id = db.Column(db.Integer, db.ForeignKey("files.id"), nullable=False, unique=True)
    run_key = db.Column(db.Text, nullable=False, default="")
    old_agent_text = db.Column(db.Text, nullable=False, default="")
    new_agent_text = db.Column(db.Text, nullable=False, default="")
    old_document_json = db.Column(db.Text, nullable=False, default="")
    new_document_json = db.Column(db.Text, nullable=False, default="")
    object_updates = db.Column(JSONB, nullable=False, default=dict)
    tool = db.Column(db.Text, nullable=False, default="patch_file")
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    def to_dict(self):
        return {
            "id": self.id,
            "workspace_id": self.workspace_id,
            "topic_id": self.topic_id,
            "file_id": self.file_id,
            "run_key": self.run_key or "",
            "old_agent_text": self.old_agent_text or "",
            "new_agent_text": self.new_agent_text or "",
            "old_document_json": self.old_document_json or "",
            "new_document_json": self.new_document_json or "",
            "object_updates": self.object_updates if self.object_updates is not None else {},
            "tool": self.tool or "patch_file",
            "created_at": _iso(self.created_at),
        }
