from routes.blocks import blocks_bp
from routes.files import files_bp
from routes.task_views import task_views_bp
from routes.tasks import tasks_bp
from routes.topics import topics_bp
from routes.upload import upload_bp
from routes.view_sections import view_sections_bp


def register_blueprints(app):
    app.register_blueprint(topics_bp)
    app.register_blueprint(files_bp)
    app.register_blueprint(blocks_bp)
    app.register_blueprint(tasks_bp)
    app.register_blueprint(task_views_bp)
    app.register_blueprint(view_sections_bp)
    app.register_blueprint(upload_bp)
