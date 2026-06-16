-- Archive support.
ALTER TABLE topics ADD COLUMN IF NOT EXISTS archived_at TIMESTAMP;
ALTER TABLE files ADD COLUMN IF NOT EXISTS archived_at TIMESTAMP;
ALTER TABLE blocks ADD COLUMN IF NOT EXISTS archived_at TIMESTAMP;
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS archived_at TIMESTAMP;

CREATE INDEX IF NOT EXISTS idx_topics_archived_at ON topics (archived_at);
CREATE INDEX IF NOT EXISTS idx_files_archived_at ON files (archived_at);
CREATE INDEX IF NOT EXISTS idx_blocks_archived_at ON blocks (archived_at);
CREATE INDEX IF NOT EXISTS idx_tasks_archived_at ON tasks (archived_at);

-- User-configured automation rules.
CREATE TABLE IF NOT EXISTS automation_rules (
    id SERIAL PRIMARY KEY,
    key TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    action_type TEXT NOT NULL,
    trigger_type TEXT NOT NULL DEFAULT 'schedule',
    schedule TEXT NOT NULL,
    timezone TEXT NOT NULL DEFAULT 'UTC',
    params JSONB NOT NULL DEFAULT '{}',
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    last_run_at TIMESTAMP,
    next_run_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_automation_rules_due
    ON automation_rules (enabled, next_run_at);

CREATE TABLE IF NOT EXISTS automation_runs (
    id SERIAL PRIMARY KEY,
    rule_id INTEGER REFERENCES automation_rules(id),
    status TEXT NOT NULL,
    started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    finished_at TIMESTAMP,
    result JSONB NOT NULL DEFAULT '{}',
    error TEXT
);

CREATE INDEX IF NOT EXISTS idx_automation_runs_rule_started
    ON automation_runs (rule_id, started_at);

-- Pending AI suggestions created by automation or future AI preview flows.
CREATE TABLE IF NOT EXISTS ai_proposals (
    id SERIAL PRIMARY KEY,
    topic_id INTEGER REFERENCES topics(id),
    target_file_id INTEGER REFERENCES files(id),
    proposal_type TEXT NOT NULL,
    payload JSONB NOT NULL DEFAULT '{}',
    status TEXT NOT NULL DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    decided_at TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_ai_proposals_pending
    ON ai_proposals (status, topic_id, target_file_id);
