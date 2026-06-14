-- Section pane ordering on placeholder rows in task_views.
ALTER TABLE task_views ADD COLUMN IF NOT EXISTS order_index INTEGER DEFAULT 0;
