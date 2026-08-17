-- Saved AI actions: an icon, and a slot on the AI bar (1..6, NULL = menu only).
ALTER TABLE automations ADD COLUMN IF NOT EXISTS icon TEXT NOT NULL DEFAULT '';
ALTER TABLE automations ADD COLUMN IF NOT EXISTS bar_slot INTEGER;

CREATE UNIQUE INDEX IF NOT EXISTS automations_workspace_bar_slot_uidx
  ON automations (workspace_id, bar_slot)
  WHERE bar_slot IS NOT NULL;
