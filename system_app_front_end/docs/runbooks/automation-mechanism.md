# Automation Mechanism

Automation is configured by the user and executed by the backend. The frontend exposes the rules, archive access, and AI proposal decisions.

## User-Facing Contract

- Automations are visible from the global Automations menu.
- The menu shows each main automation as a compact row with its current timing, an enable/disable switch, an edit-time action, and a run-now action for testing.
- Timing opens in a separate dialog with structured controls: once a day, once a week, or once a month. Daily schedules choose a time. Weekly schedules choose a calendar day and time. Monthly schedules choose a calendar day, time, and month placement such as the first, second, third, or last Monday.
- **Run now is non-blocking:** the app enqueues the run, shows “Automation started”, and polls run status in the background.
- When a run completes, the open app refreshes the current topic or task view so new and archived files are visible. If no topic or view is open, content refresh is skipped.
- A 30-second rule poll remains as a fallback for scheduled runs that complete while the app was in the background.
- Archived content appears in a sidebar Archive section and does not compete with active topics.
- AI-generated process suggestions are pending until the user approves them.

## Backend queue flow

```text
Trigger (schedule / manual / file change)
  → POST or internal enqueue → automation_runs.status = queued
  → Render cron processes queue → running → success | failed
  → Flutter polls GET /automation_runs while active
```

Event-triggered rules (`trigger_type=event`) match `params.event=file_changed` and `params.file_id` against file/block/task mutations on the backend. Event rules do not use the schedule UI.

## Initial Rules

| Rule | Default Timing | Behavior |
| --- | --- | --- |
| Daily rotation | Every day at 00:00 | Archive current main-topic `Daily` file and create a new `Daily` text file. |
| Weekly process refresh | Weekly | For each process, find plan/doc/tasks files and create a smart-update proposal. After user review, archive old files and recreate plan, empty doc table, and tasks. |

## AI Proposals

AI proposal generation is an AI concern, not a general automation concern. Automation creates the moment when proposals are requested; the proposal layer stores suggested content and exposes review/finalize actions.

The `process_smart_update` AI action reads plan, documentation, and tasks as flattened units with stable IDs, returns edit operations, and stores a reusable `change_set`. Finalize archives the old files and creates fresh plan, empty documentation table, and tasks files after review.

Skipped processes create a `process_refresh_skipped` warning proposal on the process topic.

Change review UI lives in `lib/shared/change_review/` and works with any automation that produces a `change_set`.

## Archive

Archive uses `archived_at` timestamps from the backend. Normal active lists hide archived rows. Archive views request data with `include_archived=true` and filter for archived rows locally when needed.

## Frontend files

- `lib/core/models/automation_run.dart` — run status model
- `lib/core/services/automation_service.dart` — rules + run status API
- `lib/core/app_state.dart` — active run tracking and polling
- `lib/features/shell/automation_dialog.dart` — run-now UI
- `lib/features/shell/app_shell.dart` — completion snackbars
