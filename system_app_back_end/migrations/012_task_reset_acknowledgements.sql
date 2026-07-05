-- One-time user acknowledgement after scheduled task-view reset automation runs.
CREATE TABLE IF NOT EXISTS task_reset_acknowledgements (
    id SERIAL PRIMARY KEY,
    automation_run_id INTEGER REFERENCES automation_runs(id),
    rule_id INTEGER REFERENCES automation_rules(id),
    view_type TEXT NOT NULL,
    report_file_id INTEGER REFERENCES files(id),
    payload JSONB NOT NULL DEFAULT '{}',
    status TEXT NOT NULL DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT NOW(),
    approved_at TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_task_reset_ack_pending_view
    ON task_reset_acknowledgements (view_type, status, created_at);
