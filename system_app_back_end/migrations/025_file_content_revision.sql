-- Optimistic concurrency for document_json: client sends base_revision on PATCH;
-- mismatch → 409 with the current file (no blind overwrite).
ALTER TABLE files
  ADD COLUMN IF NOT EXISTS content_revision INTEGER NOT NULL DEFAULT 1;
