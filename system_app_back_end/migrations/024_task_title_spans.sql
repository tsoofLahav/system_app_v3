-- Task title inline styles (bold / italic / …), same shape as info metadata spans.
ALTER TABLE tasks
  ADD COLUMN IF NOT EXISTS title_spans JSONB NOT NULL DEFAULT '[]'::jsonb;
