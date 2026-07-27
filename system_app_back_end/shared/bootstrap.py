from models import File, Tag, Topic, Workspace, db
from areas.files.services.document_v3 import empty_document_json
from areas.production_agent.services.prompt import ensure_agent_config


def bootstrap_if_empty() -> dict:
    workspace = Workspace.query.order_by(Workspace.id).first()
    if workspace is not None:
        ensure_agent_config(workspace.id)
        db.session.commit()
        return {"ready": True, "workspace_id": workspace.id, "created": False}

    workspace = Workspace(name="Default")
    db.session.add(workspace)
    db.session.flush()

    home = Topic(
        workspace_id=workspace.id,
        name="Home",
        icon="🏠",
        color="#6366F1",
        order_index=0,
    )
    db.session.add(home)
    db.session.flush()

    daily = File(
        topic_id=home.id,
        name="Daily",
        document_json=empty_document_json(),
        order_index=0,
        meta={"automation_anchor": "daily"},
    )
    db.session.add(daily)

    for tag_name in ("project", "process", "area", "other"):
        db.session.add(
            Tag(workspace_id=workspace.id, name=tag_name, color=None)
        )

    ensure_agent_config(workspace.id)

    db.session.commit()
    return {
        "ready": True,
        "workspace_id": workspace.id,
        "created": True,
        "home_topic_id": home.id,
        "daily_file_id": daily.id,
    }


def default_workspace_id() -> int | None:
    workspace = Workspace.query.order_by(Workspace.id).first()
    return workspace.id if workspace else None
