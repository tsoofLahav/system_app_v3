-- Single view membership per task + file settings for flip-by-view mode.

-- Dedupe: keep highest-priority view per task (daily > weekly > monthly > ...).
WITH ranked AS (
    SELECT
        id,
        task_id,
        ROW_NUMBER() OVER (
            PARTITION BY task_id
            ORDER BY
                CASE view_type
                    WHEN 'daily' THEN 0
                    WHEN 'weekly' THEN 1
                    WHEN 'monthly' THEN 2
                    WHEN 'quarterly' THEN 3
                    WHEN 'arrangements' THEN 4
                    WHEN 'missions' THEN 5
                    ELSE 99
                END,
                id
        ) AS rn
    FROM task_views
    WHERE task_id IS NOT NULL
)
DELETE FROM task_views
WHERE id IN (SELECT id FROM ranked WHERE rn > 1);

CREATE UNIQUE INDEX IF NOT EXISTS idx_task_views_task_id_unique
    ON task_views (task_id)
    WHERE task_id IS NOT NULL;

ALTER TABLE files ADD COLUMN IF NOT EXISTS settings JSONB NOT NULL DEFAULT '{}';
