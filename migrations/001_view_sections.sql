-- Run once against the PostgreSQL database.
CREATE TABLE IF NOT EXISTS view_sections (
    id SERIAL PRIMARY KEY,
    view_type TEXT NOT NULL,
    name TEXT NOT NULL,
    order_index INTEGER DEFAULT 0
);

ALTER TABLE task_views
    ADD COLUMN IF NOT EXISTS section_id INTEGER REFERENCES view_sections(id);
