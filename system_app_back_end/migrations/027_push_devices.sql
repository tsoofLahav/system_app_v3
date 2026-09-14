BEGIN;
CREATE TABLE IF NOT EXISTS push_devices (
    id SERIAL PRIMARY KEY,
    installation_id VARCHAR(36) NOT NULL UNIQUE,
    workspace_id INTEGER NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    token TEXT NOT NULL,
    environment VARCHAR(10) NOT NULL CHECK (environment IN ('sandbox', 'production')),
    language VARCHAR(2) NOT NULL DEFAULT 'en' CHECK (language IN ('en', 'he')),
    active BOOLEAN NOT NULL DEFAULT TRUE,
    last_keys JSONB NOT NULL DEFAULT '[]'::jsonb,
    last_badge INTEGER NOT NULL DEFAULT -1,
    updated_at TIMESTAMP NOT NULL DEFAULT (NOW() AT TIME ZONE 'UTC')
);
CREATE INDEX IF NOT EXISTS ix_push_devices_workspace_id ON push_devices(workspace_id);
COMMIT;
