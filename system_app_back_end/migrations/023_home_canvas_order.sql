-- Shared Home canvas order (visits interleaved with Home files). Layout stays on the topic.
ALTER TABLE workspaces
  ADD COLUMN IF NOT EXISTS home_canvas_file_ids JSONB NOT NULL DEFAULT '[]'::jsonb;
