-- Section-window automations, complimentary tasks, and AI user-input.

ALTER TABLE automations
    ADD COLUMN IF NOT EXISTS kind TEXT NOT NULL DEFAULT 'standard',
    ADD COLUMN IF NOT EXISTS view_id INTEGER REFERENCES views(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS section_key TEXT,
    ADD COLUMN IF NOT EXISTS window_duration_minutes INTEGER,
    ADD COLUMN IF NOT EXISTS window_opened_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS window_closes_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS pending_clear JSONB,
    ADD COLUMN IF NOT EXISTS pending_user_input JSONB;

ALTER TABLE tasks
    ADD COLUMN IF NOT EXISTS source_automation_id INTEGER REFERENCES automations(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS complimentary_role TEXT,
    ADD COLUMN IF NOT EXISTS complimentary_cycle JSONB NOT NULL DEFAULT '{}';

ALTER TABLE ai_actions
    ADD COLUMN IF NOT EXISTS requires_user_input BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS user_input_prompt TEXT;

CREATE INDEX IF NOT EXISTS idx_automations_kind ON automations(kind);
CREATE INDEX IF NOT EXISTS idx_automations_view_section ON automations(view_id, section_key);
CREATE INDEX IF NOT EXISTS idx_tasks_source_automation ON tasks(source_automation_id);
