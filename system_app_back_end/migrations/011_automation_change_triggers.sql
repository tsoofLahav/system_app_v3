-- Debounced change triggers for event-driven automations.
CREATE TABLE IF NOT EXISTS automation_change_triggers (
    id SERIAL PRIMARY KEY,
    rule_id INTEGER NOT NULL REFERENCES automation_rules(id) ON DELETE CASCADE,
    dedupe_key TEXT NOT NULL,
    event_context JSONB NOT NULL DEFAULT '{}',
    fire_at TIMESTAMP NOT NULL,
    dirty BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    UNIQUE (rule_id, dedupe_key)
);

CREATE INDEX IF NOT EXISTS idx_automation_change_triggers_fire_at
    ON automation_change_triggers (fire_at);
