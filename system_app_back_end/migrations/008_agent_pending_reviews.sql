-- Pending agent review proposals (lookalike diff / per-hunk accept).
CREATE TABLE IF NOT EXISTS agent_pending_reviews (
  id SERIAL PRIMARY KEY,
  workspace_id INTEGER NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  topic_id INTEGER NOT NULL REFERENCES topics(id) ON DELETE CASCADE,
  file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
  run_key TEXT NOT NULL DEFAULT '',
  old_agent_text TEXT NOT NULL DEFAULT '',
  new_agent_text TEXT NOT NULL DEFAULT '',
  old_document_json TEXT NOT NULL DEFAULT '',
  new_document_json TEXT NOT NULL DEFAULT '',
  object_updates JSONB NOT NULL DEFAULT '{}'::jsonb,
  tool TEXT NOT NULL DEFAULT 'patch_file',
  created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS agent_pending_reviews_file_id_uidx
  ON agent_pending_reviews (file_id);

CREATE INDEX IF NOT EXISTS agent_pending_reviews_topic_id_idx
  ON agent_pending_reviews (topic_id);
