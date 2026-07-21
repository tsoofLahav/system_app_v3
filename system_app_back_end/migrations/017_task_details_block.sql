-- Optional link from a task to a details block (hover preview).

ALTER TABLE tasks ADD COLUMN IF NOT EXISTS details_block_id INTEGER REFERENCES blocks(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_tasks_details_block_id ON tasks (details_block_id);
