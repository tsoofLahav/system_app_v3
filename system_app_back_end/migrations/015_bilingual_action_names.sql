-- Bilingual titles for saved AI actions and automations, and a topic
-- (not only type) scope on AI actions.

ALTER TABLE ai_actions
    ADD COLUMN IF NOT EXISTS name_he TEXT;

ALTER TABLE ai_actions
    ADD COLUMN IF NOT EXISTS topic_id INTEGER REFERENCES topics(id) ON DELETE SET NULL;

ALTER TABLE automations
    ADD COLUMN IF NOT EXISTS name_he TEXT;

UPDATE ai_actions
SET name_he = name
WHERE name_he IS NULL OR btrim(name_he) = '';

UPDATE automations
SET name_he = name
WHERE name_he IS NULL OR btrim(name_he) = '';
