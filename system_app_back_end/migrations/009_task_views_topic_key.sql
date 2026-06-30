ALTER TABLE task_views ADD COLUMN IF NOT EXISTS topic_key TEXT;

CREATE INDEX IF NOT EXISTS idx_task_views_topic_key
    ON task_views (view_type, topic_key)
    WHERE topic_key IS NOT NULL;
