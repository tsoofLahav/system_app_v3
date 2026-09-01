-- File-only active tasks become inactive until they get a view.
UPDATE tasks
SET status = 'inactive'
WHERE archived_at IS NULL
  AND status = 'active'
  AND id NOT IN (SELECT task_id FROM view_task_memberships);
