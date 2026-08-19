"""Area packages — each area owns its routes, services, and AREA.md contract.

Blueprint imports live inside `register_blueprints` so that importing a single
leaf module (e.g. a service) does not pull in every route in every area.
"""


def register_blueprints(app):
    from areas.automations.routes.automations import automations_bp
    from areas.files.routes.file_versions import file_versions_bp
    from areas.files.routes.files import files_bp
    from areas.files.routes.topic_types import topic_types_bp
    from areas.files.routes.topics import topics_bp
    from areas.objects.routes.information import information_bp
    from areas.objects.routes.objects import objects_bp
    from areas.objects.routes.task_lists import task_lists_bp
    from areas.objects.routes.tasks import tasks_bp
    from areas.objects.routes.views import views_bp
    from areas.production_agent.routes.agent import agent_bp
    from areas.production_agent.routes.ai_actions import ai_actions_bp
    from shared.routes.bootstrap import bootstrap_bp
    from shared.routes.tags import tags_bp
    from shared.routes.upload import upload_bp
    from shared.routes.workspaces import workspaces_bp

    app.register_blueprint(bootstrap_bp)
    app.register_blueprint(workspaces_bp)
    app.register_blueprint(topics_bp)
    app.register_blueprint(topic_types_bp)
    app.register_blueprint(files_bp)
    app.register_blueprint(file_versions_bp)
    app.register_blueprint(objects_bp)
    app.register_blueprint(tasks_bp)
    app.register_blueprint(task_lists_bp)
    app.register_blueprint(information_bp)
    app.register_blueprint(views_bp)
    app.register_blueprint(agent_bp)
    app.register_blueprint(ai_actions_bp)
    app.register_blueprint(automations_bp)
    app.register_blueprint(tags_bp)
    app.register_blueprint(upload_bp)
