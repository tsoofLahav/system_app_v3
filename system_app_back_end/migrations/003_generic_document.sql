-- Phase 1: generic file document — rename body, extend objects for image/graph.

ALTER TABLE files RENAME COLUMN body TO document_json;

ALTER TABLE objects ADD COLUMN IF NOT EXISTS payload JSONB NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE objects DROP CONSTRAINT IF EXISTS objects_type_check;
ALTER TABLE objects DROP CONSTRAINT IF EXISTS objects_check;
ALTER TABLE objects DROP CONSTRAINT IF EXISTS objects_entity_check;

ALTER TABLE objects ADD CONSTRAINT objects_type_check
    CHECK (type IN ('task_list', 'info', 'image', 'graph'));

ALTER TABLE objects ADD CONSTRAINT objects_entity_check CHECK (
    (type = 'task_list' AND task_list_id IS NOT NULL AND information_id IS NULL)
    OR (type = 'info' AND information_id IS NOT NULL AND task_list_id IS NULL)
    OR (type IN ('image', 'graph') AND task_list_id IS NULL AND information_id IS NULL)
);
