-- User-defined topic types. Classification is no longer a magic tag name.

CREATE TABLE IF NOT EXISTS topic_types (
    id SERIAL PRIMARY KEY,
    workspace_id INTEGER NOT NULL REFERENCES workspaces(id),
    name TEXT NOT NULL,
    order_index INTEGER NOT NULL DEFAULT 0,
    template_topic_id INTEGER REFERENCES topics(id) ON DELETE SET NULL,
    UNIQUE (workspace_id, name)
);

ALTER TABLE topics
    ADD COLUMN IF NOT EXISTS topic_type_id INTEGER REFERENCES topic_types(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_topics_topic_type_id ON topics (topic_type_id);

ALTER TABLE ai_actions
    ADD COLUMN IF NOT EXISTS topic_type_id INTEGER REFERENCES topic_types(id) ON DELETE SET NULL;

-- Four seeded classification tags become types. Names stay as the user saw them.
INSERT INTO topic_types (workspace_id, name, order_index)
SELECT DISTINCT tags.workspace_id, tags.name,
    CASE tags.name
        WHEN 'project' THEN 0
        WHEN 'process' THEN 1
        WHEN 'area' THEN 2
        ELSE 3
    END
FROM tags
WHERE tags.name IN ('project', 'process', 'area', 'other')
ON CONFLICT (workspace_id, name) DO NOTHING;

UPDATE topics
SET topic_type_id = tt.id
FROM entity_tags et
JOIN tags ON tags.id = et.tag_id
JOIN topic_types tt
    ON tt.workspace_id = tags.workspace_id
   AND tt.name = tags.name
WHERE et.entity_type = 'topic'
  AND et.entity_id = topics.id
  AND tags.name IN ('project', 'process', 'area', 'other')
  AND topics.topic_type_id IS NULL;

-- Automations scoped by the old tag name now point at the type id.
UPDATE automations a
SET scope = (a.scope - 'tag') || jsonb_build_object('topic_type_id', tt.id)
FROM topic_types tt
WHERE a.workspace_id = tt.workspace_id
  AND a.scope->>'kind' = 'topic_type'
  AND a.scope->>'tag' = tt.name
  AND a.scope ? 'tag';
