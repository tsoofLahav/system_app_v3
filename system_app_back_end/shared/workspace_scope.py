"""Workspace selection for local presentation profiles, not authentication."""
from flask import abort, g, has_request_context, request
from sqlalchemy import event, select, or_
from sqlalchemy.orm import Session, with_loader_criteria
import models as m


def selected_workspace_id():
    return getattr(g, 'selected_workspace_id', None) if has_request_context() else None


def scope_rules(wid):
    # Core selects deliberately use tables so ORM criteria do not recurse.
    t, f, o = m.Topic.__table__, m.File.__table__, m.ObjectEmbed.__table__
    topics = select(t.c.id).where(t.c.workspace_id == wid)
    files = select(f.c.id).where(f.c.topic_id.in_(topics))
    objects = select(o.c.id).where(o.c.file_id.in_(files))
    lists = select(o.c.task_list_id).where(o.c.file_id.in_(files))
    infos = select(o.c.information_id).where(o.c.file_id.in_(files))
    v, vm = m.View.__table__, m.ViewTaskMembership.__table__
    views = select(v.c.id).where(v.c.workspace_id == wid)
    view_tasks = select(vm.c.task_id).where(vm.c.view_id.in_(views))
    tasks = select(m.Task.__table__.c.id).where(or_(m.Task.__table__.c.task_list_id.in_(lists), m.Task.__table__.c.id.in_(view_tasks)))
    rules = [(model, model.workspace_id == wid) for model in
             (m.Topic, m.TopicType, m.Tag, m.Link, m.View, m.AiAction,
              m.Automation, m.AgentConfig, m.AgentPendingReview)]
    rules += [(m.File, m.File.topic_id.in_(topics)),
              (m.ObjectEmbed, m.ObjectEmbed.file_id.in_(files)),
              (m.TaskList, m.TaskList.id.in_(lists)),
              (m.InformationPiece, m.InformationPiece.id.in_(infos)),
              (m.Task, m.Task.id.in_(tasks)),
              (m.FileVersion, m.FileVersion.file_id.in_(files)),
              (m.ViewTaskMembership, m.ViewTaskMembership.view_id.in_(views)),
              (m.AutomationRun, m.AutomationRun.automation_id.in_(select(m.Automation.__table__.c.id).where(m.Automation.__table__.c.workspace_id == wid))),
              (m.EntityTag, m.EntityTag.tag_id.in_(select(m.Tag.__table__.c.id).where(m.Tag.__table__.c.workspace_id == wid)))]
    return rules


@event.listens_for(Session, 'do_orm_execute')
def scoped_queries(state):
    wid = selected_workspace_id()
    if wid is None or state.execution_options.get('skip_workspace_scope'):
        return
    if state.is_select:
        state.statement = state.statement.options(*[
            with_loader_criteria(model, clause, include_aliases=True)
            for model, clause in scope_rules(wid)
        ])


REFERENCE_MODELS = {
    'topic_id': m.Topic, 'template_topic_id': m.Topic,
    'file_id': m.File, 'focused_file_id': m.File, 'target_file_id': m.File,
    'object_id': m.ObjectEmbed, 'source_object_id': m.ObjectEmbed,
    'target_object_id': m.ObjectEmbed, 'task_id': m.Task,
    'task_list_id': m.TaskList, 'target_task_list_id': m.TaskList,
    'information_id': m.InformationPiece, 'view_id': m.View,
    'tag_id': m.Tag, 'topic_type_id': m.TopicType,
    'automation_id': m.Automation, 'action_id': m.AiAction,
    'link_id': m.Link,
}


def validate_references(value, wid):
    if isinstance(value, list):
        for item in value:
            validate_references(item, wid)
    elif isinstance(value, dict):
        for key, item in value.items():
            if key == 'workspace_id' and item is not None and int(item) != wid:
                abort(403, description='Workspace does not match the selected profile')
            model = REFERENCE_MODELS.get(key)
            if model is not None and item is not None:
                if m.db.session.get(model, int(item)) is None:
                    abort(404, description='Item is not in the selected workspace')
            if isinstance(item, (dict, list)):
                validate_references(item, wid)


def register_workspace_scope(app):
    @app.before_request
    def select_workspace():
        raw = request.headers.get('X-Workspace-Id')
        if not raw:
            return  # Existing clients retain the original default workspace.
        try:
            wid = int(raw)
        except ValueError:
            abort(400, description='Invalid workspace profile')
        if m.db.session.get(m.Workspace, wid) is None:
            abort(404, description='Workspace not found')
        g.selected_workspace_id = wid
        validate_references(request.view_args or {}, wid)
        validate_references(request.args.to_dict(), wid)
        validate_references(request.get_json(silent=True) or {}, wid)
