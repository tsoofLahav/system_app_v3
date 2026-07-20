-- Per-list task order (independent of file block layout).

ALTER TABLE tasks ADD COLUMN IF NOT EXISTS list_order_index INTEGER NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_tasks_block_list_order
    ON tasks (block_id, list_order_index);

-- Backfill: active tasks first, then done; within each zone by task row block order.
WITH task_rows AS (
    SELECT
        t.id AS task_id,
        t.block_id,
        t.status,
        b.order_index AS row_order
    FROM tasks t
    JOIN blocks list ON list.id = t.block_id AND list.type = 'task_list'
    LEFT JOIN blocks b ON b.type = 'task'
        AND b.file_id = list.file_id
        AND (b.content ->> 'task_id') ~ '^[0-9]+$'
        AND (b.content ->> 'task_id')::int = t.id
    WHERE t.archived_at IS NULL
),
ordered AS (
    SELECT
        task_id,
        ROW_NUMBER() OVER (
            PARTITION BY block_id
            ORDER BY
                CASE WHEN status = 'done' THEN 1 ELSE 0 END,
                COALESCE(row_order, 2147483647),
                task_id
        ) - 1 AS new_list_order_index
    FROM task_rows
)
UPDATE tasks t
SET list_order_index = o.new_list_order_index
FROM ordered o
WHERE t.id = o.task_id;
