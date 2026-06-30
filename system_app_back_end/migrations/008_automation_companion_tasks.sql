CREATE TABLE IF NOT EXISTS automation_companion_tasks (
    id SERIAL PRIMARY KEY,
    task_id INTEGER NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    rule_key TEXT NOT NULL,
    automation_run_id INTEGER REFERENCES automation_runs(id),
    flow_key TEXT NOT NULL,
    topic_id INTEGER REFERENCES topics(id),
    payload JSONB NOT NULL DEFAULT '{}',
    status TEXT NOT NULL DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_automation_companion_tasks_status
    ON automation_companion_tasks (status, rule_key);

CREATE INDEX IF NOT EXISTS idx_automation_companion_tasks_task
    ON automation_companion_tasks (task_id);
