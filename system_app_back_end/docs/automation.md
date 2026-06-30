# Automation, Archive, and AI Proposals

Automation is the app-owned action system. It runs explicit rules without a user click, either on a schedule or from an event. The backend owns execution so automations still run when the Flutter app is closed.

## Concepts

- `automation_rules` stores user-configurable rules: action type, trigger type, schedule, timezone, params, enabled state, and last/next run times.
- `automation_runs` records each queued and completed attempt for auditability, status polling, and deduplication.
- `archived_at` is the soft-history marker for topics, files, blocks, and tasks. Archived data stays accessible but is hidden from normal lists by default.
- `ai_proposals` stores suggested changes that require user approval. Automation can request proposals, but AI proposal creation and approval live in the AI layer.

## Execution model

Automations are **non-blocking**:

1. A trigger enqueues a row in `automation_runs` with `status=queued`.
2. Render Cron runs `python scripts/run_automations.py`, which enqueues due schedule rules and processes the queue.
3. The worker claims queued runs (`queued` → `running` → `success` | `failed`).
4. Rules update `last_run_at` and `next_run_at` after **successful** execution.

Run statuses: `queued`, `running`, `success`, `failed`.

Each run stores:

- `trigger_source`: `schedule`, `manual`, or `event`
- `event_context`: JSON payload for event-triggered runs (for example `file_changed`)

**Dedupe:** if a rule already has a `queued` or `running` run, new enqueue requests are ignored for that rule.

## Trigger types

| `trigger_type` | When it fires |
| --- | --- |
| `schedule` | Cron enqueues when `next_run_at <= now` |
| `event` | Backend dispatches after matching domain events (v1: `file_changed`) |
| manual | `POST /automation_rules/<id>/run` enqueues immediately |

### Event rules (v1)

Event rules use `trigger_type=event` and omit `schedule`.

```json
{
  "trigger_type": "event",
  "action_type": "your_action",
  "params": {
    "event": "file_changed",
    "file_id": 42
  }
}
```

`dispatch_file_changed` runs after commits on file PATCH, block create/update/delete, and task create/update/delete for the resolved file.

## Automatic Actions

The initial action library contains:

- `create_file_by_time`: create a file with configured topic, name, type, visibility, and default block contents.
- `archive_at_time`: archive a topic, file, block, or task at a configured time.
- `rotate_daily_main_file`: archive the current main-topic `Daily` file and create a fresh `Daily` text file every day at 00:00.
- `weekly_process_refresh`: for each process, locate plan/doc/tasks files by type order, call the smart process update AI action, and store a delta proposal. Finalize archives old files and recreates plan, empty documentation table, and tasks after user review.

## Scheduling

### Run now (manual test)

`POST /automation_rules/<id>/run` enqueues the run and immediately starts background processing for **that run id**. The HTTP response returns `202` without waiting for the action to finish.

### Scheduled and event automations

Render Cron (configured in the Render dashboard, not in application code) should execute every minute:

```bash
cd system_app_back_end && python scripts/run_automations.py
```

Use the same repo, branch, and environment group as the web service so `DATABASE_URL` is available.

The script enqueues due enabled schedule rules and processes up to five queued runs per invocation.

Rule schedules use simple text values produced by the frontend controls. Times are interpreted in each rule's `timezone` (default `Asia/Jerusalem` for built-in rules). `next_run_at` is stored in UTC.

- `daily HH:MM` runs once a day at a 24-hour time in the rule timezone.
- `weekly DAY HH:MM` runs once a week on a weekday such as `mon` or `friday`.
- `monthly PLACEMENT DAY HH:MM` runs once a month on the `first`, `second`, `third`, or `last` matching weekday, for example `monthly last mon 09:00`.

## ChangeSet (reusable diff contract)

Automations and AI actions can store reviewable edits as `change_set` version 1:

- `documents[]` each have `key`, `title`, `units[]`, and `changes[]`.
- `units` use stable derived IDs such as `block:12:item:1`, `block:12:sent:0`, or `task:5`.
- Documentation tables are flattened to read-only prose for the AI (not edited via unit ops).
- `changes` list only modified units (`replace`, `remove`, `add_after`).
- AI actions return edit operations on unit IDs; `services/diff_engine.py` builds the change set.
- Finalize applies accepted changes through `services/unit_mapper.py`.

## API Ownership

- CRUD for rules is exposed through `/automation_rules`.
- Manual execution for testing is exposed through `POST /automation_rules/<id>/run` (returns `202` with a queued run and processes that run in a background thread).
- Run status is exposed through `GET /automation_runs/<id>` and `GET /automation_runs?status=queued,running`.
- Process update finalize is exposed through `POST /ai_proposals/<id>/finalize`.
- AI proposals are exposed through `/ai_proposals` and approval/rejection endpoints.
- Archive is exposed through normal resource PATCH fields and by `include_archived=true` list query parameters.

## Migration

Apply [`migrations/007_automation_run_queue.sql`](../migrations/007_automation_run_queue.sql) before deploying queue support.
