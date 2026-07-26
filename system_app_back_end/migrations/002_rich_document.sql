-- Rich document model: task lists as objects, JSON body nodes.

CREATE TABLE task_lists (
    id SERIAL PRIMARY KEY,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE tasks ADD COLUMN task_list_id INTEGER REFERENCES task_lists(id) ON DELETE CASCADE;

ALTER TABLE objects DROP CONSTRAINT IF EXISTS objects_type_check;
ALTER TABLE objects DROP CONSTRAINT IF EXISTS objects_check;

ALTER TABLE objects ADD COLUMN task_list_id INTEGER REFERENCES task_lists(id) ON DELETE CASCADE;
ALTER TABLE objects DROP COLUMN IF EXISTS task_id;

ALTER TABLE objects ADD CONSTRAINT objects_type_check
    CHECK (type IN ('task_list', 'info'));

ALTER TABLE objects ADD CONSTRAINT objects_entity_check CHECK (
    (type = 'task_list' AND task_list_id IS NOT NULL AND information_id IS NULL)
    OR (type = 'info' AND information_id IS NOT NULL AND task_list_id IS NULL)
);

CREATE INDEX idx_tasks_task_list ON tasks(task_list_id);
CREATE INDEX idx_objects_task_list ON objects(task_list_id);
