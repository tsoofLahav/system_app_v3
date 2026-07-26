from routes.agent import agent_bp
from routes.automations import automations_bp
from routes.bootstrap import bootstrap_bp
from routes.file_versions import file_versions_bp
from routes.files import files_bp
from routes.information import information_bp
from routes.objects import objects_bp
from routes.tags import tags_bp
from routes.task_lists import task_lists_bp
from routes.tasks import tasks_bp
from routes.topics import topics_bp
from routes.upload import upload_bp
from routes.views import views_bp
from routes.workspaces import workspaces_bp


def register_blueprints(app):
    app.register_blueprint(bootstrap_bp)
    app.register_blueprint(workspaces_bp)
    app.register_blueprint(topics_bp)
    app.register_blueprint(files_bp)
    app.register_blueprint(objects_bp)
    app.register_blueprint(tasks_bp)
    app.register_blueprint(task_lists_bp)
    app.register_blueprint(information_bp)
    app.register_blueprint(tags_bp)
    app.register_blueprint(views_bp)
    app.register_blueprint(agent_bp)
    app.register_blueprint(automations_bp)
    app.register_blueprint(file_versions_bp)
    app.register_blueprint(upload_bp)
