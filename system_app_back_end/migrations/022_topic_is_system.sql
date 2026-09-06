-- Built-in topics (Reports) stay out of the live sidebar and are not user-editable.

ALTER TABLE topics
    ADD COLUMN IF NOT EXISTS is_system BOOLEAN NOT NULL DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS idx_topics_is_system ON topics (is_system)
    WHERE is_system;
