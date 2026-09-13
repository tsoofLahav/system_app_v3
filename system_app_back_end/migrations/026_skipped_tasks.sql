-- Run once before deploying the missed-task changes. All timestamps are UTC.
BEGIN;
CREATE TABLE IF NOT EXISTS skipped_tasks (
    id SERIAL PRIMARY KEY,
    workspace_id INTEGER NOT NULL,
    task_id INTEGER NOT NULL,
    task_title TEXT NOT NULL,
    topic_id INTEGER,
    topic_name TEXT,
    task_list_id INTEGER,
    task_list_title TEXT,
    view_id INTEGER NOT NULL,
    view_name TEXT NOT NULL,
    section_key TEXT NOT NULL,
    section_name TEXT NOT NULL,
    automation_id INTEGER NOT NULL,
    window_opened_at TIMESTAMP WITHOUT TIME ZONE NOT NULL,
    skipped_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT (now() AT TIME ZONE 'UTC'),
    CONSTRAINT uq_skipped_task_occurrence UNIQUE (automation_id, window_opened_at, task_id)
);
CREATE INDEX IF NOT EXISTS ix_skipped_tasks_workspace_task_time
    ON skipped_tasks (workspace_id, task_id, skipped_at);
CREATE INDEX IF NOT EXISTS ix_skipped_tasks_workspace_topic_time
    ON skipped_tasks (workspace_id, topic_id, skipped_at);
COMMIT;
