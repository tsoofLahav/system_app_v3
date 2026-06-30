from routes.ai import ai_bp
from routes.ai_proposals import ai_proposals_bp
from routes.automation_companion import automation_companion_bp
from routes.automation_rules import automation_rules_bp
from routes.automation_runs import automation_runs_bp
from routes.blocks import blocks_bp
from routes.files import files_bp
from routes.task_views import task_views_bp
from routes.tasks import tasks_bp
from routes.topics import topics_bp
from routes.upload import upload_bp


def register_blueprints(app):
    app.register_blueprint(ai_bp)
    app.register_blueprint(ai_proposals_bp)
    app.register_blueprint(automation_rules_bp)
    app.register_blueprint(automation_companion_bp)
    app.register_blueprint(automation_runs_bp)
    app.register_blueprint(topics_bp)
    app.register_blueprint(files_bp)
    app.register_blueprint(blocks_bp)
    app.register_blueprint(tasks_bp)
    app.register_blueprint(task_views_bp)
    app.register_blueprint(upload_bp)
