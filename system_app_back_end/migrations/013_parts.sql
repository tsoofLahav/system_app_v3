-- Project parts: topic-scoped entities with optional block membership.

CREATE TABLE IF NOT EXISTS parts (
  id SERIAL PRIMARY KEY,
  topic_id INTEGER NOT NULL REFERENCES topics(id),
  name TEXT NOT NULL,
  order_index INTEGER NOT NULL DEFAULT 0,
  archived_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_parts_topic_id ON parts(topic_id);
CREATE INDEX IF NOT EXISTS idx_parts_topic_order ON parts(topic_id, order_index);

ALTER TABLE blocks ADD COLUMN IF NOT EXISTS part_id INTEGER REFERENCES parts(id);

CREATE INDEX IF NOT EXISTS idx_blocks_part_id ON blocks(part_id);
