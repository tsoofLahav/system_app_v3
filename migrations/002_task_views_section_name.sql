-- Single-table view sections: section_name on task_views.
-- Section placeholders use task_id NULL + section_name set.
-- Task memberships use task_id + view_type + optional section_name.

-- Remove previous two-table approach if applied:
DROP TABLE IF EXISTS view_sections CASCADE;
ALTER TABLE task_views DROP COLUMN IF EXISTS section_id;

-- Add section label column
ALTER TABLE task_views ADD COLUMN IF NOT EXISTS section_name TEXT;

-- Allow placeholder rows (sections without tasks yet)
ALTER TABLE task_views ALTER COLUMN task_id DROP NOT NULL;
