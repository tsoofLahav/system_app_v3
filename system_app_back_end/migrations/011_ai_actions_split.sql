-- Saved AI actions leave the automations table.
--
-- They only ever shared it because both stored a prompt. They are not the same
-- thing: an action is a button you press, an automation is a scope, a trigger
-- and a series of steps. Sharing the table also meant the every-minute cron
-- loop could see a bar button, which is how saved actions ended up firing 1,440
-- times a day. After this they are invisible to it.
--
-- An action has no scope column: it always runs on whatever is open, which is
-- what `run_scope()` already preferred over anything stored.

CREATE TABLE IF NOT EXISTS ai_actions (
  id SERIAL PRIMARY KEY,
  workspace_id INTEGER NOT NULL REFERENCES workspaces(id),
  name TEXT NOT NULL,
  prompt TEXT NOT NULL DEFAULT '',
  apply_mode TEXT NOT NULL DEFAULT 'direct_apply'
    CHECK (apply_mode IN ('review', 'direct_apply', 'notify_only')),
  icon TEXT NOT NULL DEFAULT '',
  bar_slot INTEGER,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS ai_actions_workspace_bar_slot_uidx
  ON ai_actions (workspace_id, bar_slot)
  WHERE bar_slot IS NOT NULL;

-- Move the manual rows across. A row with no schedule was an action whatever
-- its trigger says.
INSERT INTO ai_actions
  (workspace_id, name, prompt, apply_mode, icon, bar_slot, created_at, updated_at)
SELECT workspace_id, name, prompt, apply_mode, icon, bar_slot, created_at, updated_at
FROM automations
WHERE trigger->>'type' = 'manual'
   OR schedule IS NULL
   OR schedule = '';

DELETE FROM automation_runs WHERE automation_id IN (
  SELECT id FROM automations
  WHERE trigger->>'type' = 'manual' OR schedule IS NULL OR schedule = ''
);

DELETE FROM automations
WHERE trigger->>'type' = 'manual'
   OR schedule IS NULL
   OR schedule = '';

-- What is left is a real automation: a series of steps, each carrying its own
-- apply mode, instead of one prompt for the whole row.
ALTER TABLE automations ADD COLUMN IF NOT EXISTS steps JSONB NOT NULL DEFAULT '[]'::jsonb;

UPDATE automations
SET steps = jsonb_build_array(
  jsonb_build_object('kind', 'ai', 'prompt', prompt, 'apply_mode', apply_mode)
)
WHERE steps = '[]'::jsonb AND COALESCE(prompt, '') <> '';

DROP INDEX IF EXISTS automations_workspace_bar_slot_uidx;

ALTER TABLE automations DROP COLUMN IF EXISTS prompt;
ALTER TABLE automations DROP COLUMN IF EXISTS apply_mode;
ALTER TABLE automations DROP COLUMN IF EXISTS icon;
ALTER TABLE automations DROP COLUMN IF EXISTS bar_slot;
