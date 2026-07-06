# Automation Mechanism

Automation is configured by the user and executed by the backend. The frontend exposes the rules, archive access, and AI proposal decisions.

## User-Facing Contract

- Automations are visible from the global Automations menu.
- The menu shows each main automation as a compact row with its current timing, an enable/disable switch, an edit-time action, and a run-now action for testing.
- Timing opens in a separate dialog with structured controls: once a day, once a week, or once a month. Daily schedules choose a time. Weekly schedules choose a calendar day and time. Monthly schedules choose a calendar day, time, and month placement such as the first, second, third, or last Monday. The task-view reset automation uses one grouped editor with those same locked controls per view.
- **Run now is non-blocking:** the app enqueues the run, shows “Automation started”, and polls run status in the background.
- When a run completes, the open app refreshes the current topic or task view so new and archived files are visible. If no topic or view is open, content refresh is skipped.
- A 30-second rule poll remains as a fallback for scheduled runs that complete while the app was in the background.
- Archived content appears in a sidebar Archive section and does not compete with active topics.
- AI-generated process suggestions are pending until the user approves them.

## Automation Rules

- Disabled automations do not run automatically. If a schedule/event/task run was
  already queued and the user turns the automation off before it executes, the
  backend skips that automatic run. Run now is still explicit.
- AI-generated automation output should follow the dominant language of the
  source files, not internal labels or metadata.
- Direct-write automations must make their write target clear. Recap/summary
  automations that own `overview` should not mutate source files unless that is
  documented as part of a separate automation.
- Event automations exclude their own generated overview/recap writes from
  triggering a loop.

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
| `process_refresh` | User schedule (disabled by default) | All processes | For each process, refresh plan/doc/tasks via AI proposal; companion review task in daily view. |
| `process_documentation_input` | User schedule or task trigger (disabled by default) | All processes | On schedule or uncheck, stage doc-input companions; tap task(s) to enter daily text and grade per process. |
| `process_recap_update` | On file change (enabled by default) | All processes | Regenerate process recap when plan, doc, or tasks change; direct AI write (no review). |
| `project_summary_update` | On project file change (enabled by default) | All projects | Regenerate the project overview directly from project parts, execution, documentation, and tasks. |
| `view_task_reset` | Per-view schedules (disabled by default) | Daily, weekly, monthly, quarterly task views | Uncheck completed tasks in each due view, record already-active tasks as missed, archive a report under Automations, and show a one-time acknowledgement when the view opens. |

## Process recap (`process_recap_update`)

Separate from `process_refresh`: event-driven, updates only the recap (`overview`) file.

- **Trigger:** By changes — edits to plan, documentation, or tasks in a process topic.
- **Recap blocks updated:** `summary` (narrative), `table` (recent doc updates merged by date), `task_list` (snapshot of tasks flagged important in any view).
- **No companion task** and no change-review dialog; the AI output replaces block content in place.

## Project summary (`project_summary_update`)

Projects use ordered **parts** as inner headers shared by `plan`, `execution`,
and `tasks`. This automation runs after project core-file changes and writes
directly to `overview`, like process recap.

- **Trigger:** By changes — edits to project plan, execution, documentation, or tasks.
- **Part reading:** Reads part headers from `plan`, `execution`, and `tasks`;
  it does not modify those source files.
- **Current part:** AI infers the main part in progress for overview display.
- **Overview blocks updated:** project summary, current-part header and focused
  update, flagged tasks for current part, flagged tasks from other parts, last
  three progress dates table, and ordered parts list.
- **No companion task** and no change-review dialog; the automation is a
  direct-write overview/recap flow.

## AI Proposals

AI proposal generation is an AI concern, not a general automation concern. Automation creates the moment when proposals are requested; the proposal layer stores suggested content and exposes review/finalize actions.

The `process_smart_update` AI action reads plan, documentation, and tasks as flattened units with stable IDs, returns edit operations, and stores a reusable `change_set`. Finalize archives the old files and creates fresh plan, empty documentation table, and tasks files after review.

Skipped processes create a `process_refresh_skipped` warning proposal on the process topic.

## Process documentation input (`process_documentation_input`)

Task-triggered companion flow separate from `process_refresh` and `process_recap_update`.

- **Trigger:** on a configured schedule, or when the user unchecks the automation trigger task. Both modes use the same companion task placement (view/section).
- **Dialog:** tapping the trigger task opens `process_documentation_input_dialog.dart`, modeled after the process update batch dialog.
- **Save:** `POST /process_documentation_inputs` writes `[date, text]` to the doc table and appends the grade to the doc line graph.
- **Skip:** completes the companion link without writing.
- **Registry:** `AutomationFlowRegistry` maps `flow_key=process_documentation_input` to the dialog.

Change review UI lives in `lib/shared/change_review/` and works with any automation that produces a `change_set`.

## Archive

Archive uses `archived_at` timestamps from the backend. Normal active lists hide archived rows. Archive views request data with `include_archived=true` and filter for archived rows locally when needed.

## View task reset (`view_task_reset`)

This automation is schedule-driven. The automation dialog keeps it as one main automation row, then manages four locked schedules inside that row through `params.view_resets`.

- Daily reset: time only (`daily HH:MM`).
- Weekly reset: day and time (`weekly DAY HH:MM`).
- Monthly reset: placement, day, and time (`monthly first|second|third|last DAY HH:MM`).
- Quarterly reset: same placement/day/time pattern as monthly, plus a 3-month or 4-month interval (`quarterly 3|4 PLACEMENT DAY HH:MM`). It can sync its placement/day/time with the monthly reset while keeping its own interval.

- Backend runs immediately at the scheduled time; it does not wait for app approval.
- Completed tasks are changed from done to active.
- Tasks that were already active are treated as missed and included in an archived report file under the real `Automations` topic.
- The frontend fetches pending reset acknowledgements after `selectView(viewType)` and shows the acknowledgement dialog once for that view. Approving the dialog calls `POST /task_reset_acknowledgements/<id>/approve`.

## Frontend files

- `lib/core/models/automation_definition.dart` — definition model from API
- `lib/core/services/automation_definition_service.dart` — `GET /automation_definitions`
- `lib/core/models/automation_run.dart` — run status model
- `lib/core/services/automation_service.dart` — rules + run status API
- `lib/core/app_state.dart` — definition loading, rule seeding, active run tracking
- `lib/features/shell/automation_dialog.dart` — automation UI (activations + scope from definition)
- `lib/core/models/task_reset_acknowledgement.dart` — pending view-reset acknowledgement model
- `lib/core/services/task_reset_acknowledgement_service.dart` — acknowledgement API client
- `lib/features/task_view/task_view_pane.dart` — first-open acknowledgement dialog
- `lib/core/registry/automation_flow_registry.dart` — companion `flow_key` → review dialog
- `lib/features/shell/process_documentation_input_dialog.dart` — daily doc input batch dialog
- `lib/core/services/process_documentation_input_service.dart` — write API client
- `lib/features/shell/app_shell.dart` — completion snackbars
