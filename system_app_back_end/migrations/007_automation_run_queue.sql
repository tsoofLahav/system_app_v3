-- Async automation queue: run metadata and event-only rules.
ALTER TABLE automation_runs
    ADD COLUMN IF NOT EXISTS trigger_source TEXT NOT NULL DEFAULT 'schedule';

ALTER TABLE automation_runs
    ADD COLUMN IF NOT EXISTS event_context JSONB NOT NULL DEFAULT '{}';

ALTER TABLE automation_rules
    ALTER COLUMN schedule DROP NOT NULL;

CREATE INDEX IF NOT EXISTS idx_automation_runs_active
    ON automation_runs (rule_id, status)
    WHERE status IN ('queued', 'running');
