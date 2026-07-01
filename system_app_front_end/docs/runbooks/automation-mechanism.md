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
  → enqueue → automation_runs.status = queued
  → manual: background thread processes that run id immediately
  → schedule/event: Render cron processes the queue
  → running → success | failed
  → Flutter polls GET /automation_runs while active
```

### Render Cron setup (dashboard, not code)

1. Render dashboard → **New** → **Cron Job**
2. Connect the same repo/branch as the backend web service
3. **Schedule:** `*/1 * * * *` (every minute)
4. **Command:** `cd system_app_back_end && python scripts/run_automations.py`  
   (`PYTHONPATH=.` is no longer required; the script sets its own import path.)
5. Link the same PostgreSQL database (or shared environment group) so `DATABASE_URL` is set

Event-triggered rules (`trigger_type=event`) match `params.event=file_changed` and `params.file_id` against file/block/task mutations on the backend. Event rules do not use the schedule UI.

## Automation definitions

Built-in automations are loaded from `GET /automation_definitions`. The UI seeds missing rule instances from `default_params` in each definition (not hardcoded maps in `app_state`).

- Scope is shown read-only in the automation dialog (fixed per automation in v1).
- Trigger options (schedule / task / event) are limited to each definition's `activations`.
- Companion pending links are filtered on the backend by rule scope; the frontend does not apply its own scope filter.

**Future flexibility:** editable scope and user-defined automation types are planned; v1 uses code-defined built-ins only.

## Initial Rules

Definitions drive the table below; see backend `docs/automation.md` for full registry detail.

| Key | Default timing | Scope | Behavior |
| --- | --- | --- | --- |
| `daily_rotation` | Every day at 00:00 | Main | Archive current main-topic `Daily` file and create a new `Daily` text file. |
| `weekly_process_refresh` | Weekly (disabled by default) | All processes | For each process, refresh plan/doc/tasks via AI proposal; companion review task in daily view. |

## AI Proposals

AI proposal generation is an AI concern, not a general automation concern. Automation creates the moment when proposals are requested; the proposal layer stores suggested content and exposes review/finalize actions.

The `process_smart_update` AI action reads plan, documentation, and tasks as flattened units with stable IDs, returns edit operations, and stores a reusable `change_set`. Finalize archives the old files and creates fresh plan, empty documentation table, and tasks files after review.

Skipped processes create a `process_refresh_skipped` warning proposal on the process topic.

Change review UI lives in `lib/shared/change_review/` and works with any automation that produces a `change_set`.

## Archive

Archive uses `archived_at` timestamps from the backend. Normal active lists hide archived rows. Archive views request data with `include_archived=true` and filter for archived rows locally when needed.

## Frontend files

- `lib/core/models/automation_definition.dart` — definition model from API
- `lib/core/services/automation_definition_service.dart` — `GET /automation_definitions`
- `lib/core/models/automation_run.dart` — run status model
- `lib/core/services/automation_service.dart` — rules + run status API
- `lib/core/app_state.dart` — definition loading, rule seeding, active run tracking
- `lib/features/shell/automation_dialog.dart` — automation UI (activations + scope from definition)
- `lib/core/registry/automation_flow_registry.dart` — companion `flow_key` → review dialog
- `lib/features/shell/app_shell.dart` — completion snackbars
