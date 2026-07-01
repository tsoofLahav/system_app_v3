-- Rename weekly_process_refresh automation (schedule is user-configurable; name was misleading).
UPDATE automation_rules
SET key = 'process_refresh',
    action_type = 'process_refresh'
WHERE key = 'weekly_process_refresh'
   OR action_type = 'weekly_process_refresh';
