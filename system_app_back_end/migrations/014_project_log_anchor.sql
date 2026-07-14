-- Log files anchored to a project topic while living elsewhere (e.g. main).

ALTER TABLE files ADD COLUMN IF NOT EXISTS anchor_topic_id INTEGER REFERENCES topics(id);

CREATE INDEX IF NOT EXISTS idx_files_anchor_topic_id ON files(anchor_topic_id);
