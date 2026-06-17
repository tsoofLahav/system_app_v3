# Automation, Archive, and AI Proposals

Automation is the app-owned action system. It runs explicit rules without a user click, either on a schedule or from a trigger. The backend owns scheduled execution so automations still run when the Flutter app is closed.

## Concepts

- `automation_rules` stores user-configurable rules: action type, schedule, timezone, params, enabled state, and last/next run times.
- `automation_runs` records each attempt for auditability and idempotency.
- `archived_at` is the soft-history marker for topics, files, blocks, and tasks. Archived data stays accessible but is hidden from normal lists by default.
- `ai_proposals` stores suggested changes that require user approval. Automation can request proposals, but AI proposal creation and approval live in the AI layer.

## Automatic Actions

The initial action library contains:

- `create_file_by_time`: create a file with configured topic, name, type, visibility, and default block contents.
- `archive_at_time`: archive a topic, file, block, or task at a configured time.
- `rotate_daily_main_file`: archive the current main-topic `Daily` file and create a fresh `Daily` text file every day at 00:00.
- `weekly_process_refresh`: for each process, locate plan/doc/tasks files by type order, call the smart process update AI action, and store a delta proposal. Finalize archives old files and recreates plan, empty documentation table, and tasks after user review.

## Scheduling

Render Cron should execute:

```bash
python scripts/run_automations.py
```

The script runs due enabled rules and stores a row in `automation_runs`. Rules update `last_run_at` and `next_run_at` after successful execution. Actions must be idempotent for their run window.

Rule schedules use simple text values produced by the frontend controls:

- `daily HH:MM` runs once a day at a 24-hour time.
- `weekly DAY HH:MM` runs once a week on a weekday such as `mon` or `friday`.
- `monthly PLACEMENT DAY HH:MM` runs once a month on the `first`, `second`, `third`, or `last` matching weekday, for example `monthly last mon 09:00`.

## ChangeSet (reusable diff contract)

Automations and AI actions can store reviewable edits as `change_set` version 1:

- `documents[]` each have `key`, `title`, `units[]`, and `changes[]`.
- `units` use stable derived IDs such as `block:12:item:1` or `task:5`.
- `changes` list only modified units (`replace`, `remove`, `add_after`).
- AI actions return edit operations on unit IDs; `services/diff_engine.py` builds the change set.
- Finalize applies accepted changes through `services/unit_mapper.py`.

## API Ownership

- CRUD for rules is exposed through `/automation_rules`.
- Manual execution for testing is exposed through `POST /automation_rules/<id>/run`.
- Process update finalize is exposed through `POST /ai_proposals/<id>/finalize`.
- AI proposals are exposed through `/ai_proposals` and approval/rejection endpoints.
- Archive is exposed through normal resource PATCH fields and by `include_archived=true` list query parameters.
