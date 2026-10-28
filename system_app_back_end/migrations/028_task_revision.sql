-- Apply before deploying the task save queue backend.
-- SQLAlchemy checks/increments this for every ORM task update (including agents
-- and automations), preventing late writers from replacing a newer task.
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS revision INTEGER NOT NULL DEFAULT 1;
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS creation_key TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS tasks_creation_key_unique ON tasks (creation_key);
