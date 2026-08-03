-- Object graph: tag icons, typed links with optional text anchors.
ALTER TABLE tags
  ADD COLUMN IF NOT EXISTS icon TEXT;

ALTER TABLE links
  ADD COLUMN IF NOT EXISTS kind TEXT NOT NULL DEFAULT 'related';

ALTER TABLE links
  ADD COLUMN IF NOT EXISTS anchor JSONB;

-- Remap legacy info→* edges that stored information_pieces.id as source_id
-- into objects.id when a matching info embed exists.
UPDATE links AS l
SET source_type = 'info',
    source_id = o.id
FROM objects o
WHERE l.source_type = 'info'
  AND o.type = 'info'
  AND o.information_id = l.source_id
  AND NOT EXISTS (
    SELECT 1 FROM objects o2 WHERE o2.id = l.source_id AND o2.type = 'info'
  );

CREATE INDEX IF NOT EXISTS idx_links_workspace_kind ON links (workspace_id, kind);
CREATE INDEX IF NOT EXISTS idx_links_source ON links (source_type, source_id);
CREATE INDEX IF NOT EXISTS idx_links_target ON links (target_type, target_id);
CREATE INDEX IF NOT EXISTS idx_entity_tags_entity ON entity_tags (entity_type, entity_id);
