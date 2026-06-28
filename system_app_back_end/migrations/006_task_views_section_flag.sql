-- Section importance flag on task_views (placeholders + denormalized on task rows).
ALTER TABLE task_views ADD COLUMN IF NOT EXISTS section_flag TEXT;
