-- Files visiting Home. Same file row as on the source topic; membership only.
ALTER TABLE workspaces
  ADD COLUMN IF NOT EXISTS home_visit_file_ids JSONB NOT NULL DEFAULT '[]'::jsonb;
