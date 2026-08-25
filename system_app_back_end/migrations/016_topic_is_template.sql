-- Dedicated per-type template topics stay out of the sidebar.

ALTER TABLE topics
    ADD COLUMN IF NOT EXISTS is_template BOOLEAN NOT NULL DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS idx_topics_is_template ON topics (is_template)
    WHERE is_template;
