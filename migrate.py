"""Apply idempotent SQL migrations on startup."""

from sqlalchemy import text

from models import db

_MIGRATIONS = [
    """
    CREATE TABLE IF NOT EXISTS view_sections (
        id SERIAL PRIMARY KEY,
        view_type TEXT NOT NULL,
        name TEXT NOT NULL,
        order_index INTEGER DEFAULT 0
    )
    """,
    """
    ALTER TABLE task_views
        ADD COLUMN IF NOT EXISTS section_id INTEGER REFERENCES view_sections(id)
    """,
]


def run_migrations(app):
    with app.app_context():
        for sql in _MIGRATIONS:
            db.session.execute(text(sql.strip()))
        db.session.commit()
