-- Per-file override for main vs secondary visibility on topic canvas.
ALTER TABLE files ADD COLUMN IF NOT EXISTS is_main BOOLEAN;
