-- Task list object headers (same role as info title).
ALTER TABLE task_lists
  ADD COLUMN IF NOT EXISTS title TEXT NOT NULL DEFAULT '';
