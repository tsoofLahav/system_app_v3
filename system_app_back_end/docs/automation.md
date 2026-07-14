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

**Dedupe:** if a rule already has a `queued` or `running` run, new enqueue requests are ignored for that rule. Event rules with change triggers additionally coalesce changes during an active run and schedule a follow-up when it finishes.

## Fundamental Rules

- **Enabled gate:** disabled rules must not run automatically. Schedule, task, and event dispatchers should avoid enqueueing disabled rules; the runner also skips any already-queued automatic run if the rule was disabled before execution. Manual `run now` remains an explicit user action.
- **Language preservation:** AI-backed automations must write user-visible output in the same dominant language as their source files. Prompts and language detection should avoid being biased by internal English labels, unit IDs, or block metadata.
- **Scope and bindings:** automations resolve files through definition bindings and rule params. Actions should not hardcode file names when a binding exists.
- **Self-trigger safety:** direct-write event automations must avoid triggering themselves. Overview/recap writes are excluded from file-change matching, and actions should still guard against overview-triggered runs.
- **Direct-write safety:** direct-write automations should clearly document which files they mutate. If an automation only owns an overview/recap, it must not modify source files such as plan, execution, documentation, or tasks.

## Automation definitions (registry)

Built-in automations are defined in code at `services/automation_definitions.py`. Each **definition** is the source of truth for scope, file bindings, allowed activations, companion flow, and related AI actions. A user's `automation_rules` row is an **instance**: enabled flag, schedule, timezone, trigger placement, and companion view/section overrides.

**v1 constraints:**

- The **frontend** only shows activations and scope described in each definition.
- **PATCH accepts partial or full `params`**. Updates merge into stored params (only sent fields change). After merge, params are **hydrated** from definition defaults so `scope`, `bindings`, and companion never stay empty/incomplete in storage or on GET.
- **Activation-time validation** (`validate_rule_activation`) runs when a rule is enqueued or executed. Unsupported scope, activations, or bindings fail the run with a clear error — not a 400 on config save.
- No user-authored automation types yet; the schema supports future flexible scope and DB-backed templates.

**Future flexibility (not enabled in v1):** editable scope (e.g. narrow to one process), user-defined automation types, and event-trigger UI. The registry `ScopeConfig.allowed_kinds` field is reserved for that upgrade path.

### API

- `GET /automation_definitions` — list built-in definitions
- `GET /automation_definitions/<key>` — one definition
- `GET /automation_rules` — each built-in rule may include a `definition` blob

### Built-in automations

| Key | Scope | Activations | Files (bindings) | Companion | AI |
| --- | --- | --- | --- | --- | --- |
| `daily_rotation` | Main topic | `schedule`, `manual` | `daily` → type `main`, name `Daily` | — | — |
| `process_refresh` | All `process` topics | `schedule`, `task`, `manual` | `plan`, `doc`, `tasks` | `process_update_review` in daily / Process updates | `smart_process_update` → `process_smart_update`, `process_refresh_skipped`; review `plan` + `tasks` |
| `process_documentation_input` | All `process` topics | `schedule`, `task` | `doc` | `process_documentation_input` in daily / Process documentation | — |
| `process_recap_update` | All `process` topics | `event`, `manual` | `plan`, `doc`, `tasks`, `overview` (write target) | — | `smart_process_recap_update` — direct write to recap |
| `project_summary_update` | All `project` topics | `event`, `manual` | `plan`, `execution`, `tasks`, `doc`, `overview` (write target) | — | `smart_project_summary_update` — direct write to overview |
| `project_update` | All `project` topics | `event`, `manual` | `log`, `plan`, `execution`, `tasks`, `doc` | `project_update_review` in daily / Project updates | `smart_project_update` → `project_smart_update`, `project_update_skipped`; review `plan` + `execution` + `tasks` (per part) |
| `view_task_reset` | Daily, weekly, monthly, and quarterly task views (configured by `params.view_resets`) | `schedule`, `manual` | — | one-time view acknowledgement | — |

### Instance vs definition

| Layer | User can change | Fixed |
| --- | --- | --- |
| Definition (registry) | — | scope, bindings, action, AI, flow_key |
| Rule instance (DB) | `enabled`, `schedule`, `timezone`, `trigger_type`, trigger task view/section, full `params` | `key`, `action_type` |

`PATCH /automation_rules` merges `params` as sent. Only `key` and `action_type` are rejected if changed on built-in rules. The UI should limit choices to `definition.activations`; invalid stored config surfaces when the automation runs.

## Trigger types

| `trigger_type` | When it fires |
| --- | --- |
| `schedule` | Cron enqueues when `next_run_at <= now` |
| `task` | User unchecks the trigger task (`done` → `active`) on an enabled task-triggered rule |
| `event` | Backend dispatches after matching domain events (`file_changed` on plan, doc, or tasks) |
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

### Change triggers (debounced events)

Event automations use a shared **change trigger** layer (`services/automation_change_triggers.py`), not immediate enqueue on every save.

1. **Idle debounce** — each change resets a per-rule timer (default **30s** after the last change). The automation runs only when that window elapses with no further changes.
2. **In-run coalescing** — if changes arrive while a run is already `queued` or `running`, the trigger is marked **dirty**. When the run finishes, one follow-up is scheduled (using the same idle window from the latest change).

Configuration lives on each definition as `change_trigger` and can be overridden per rule in `params.change_trigger`:

```json
{
  "change_trigger": {
    "enabled": true,
    "idle_seconds": 30,
    "coalesce_during_run": true
  }
}
```

Set `"enabled": false` on a rule to opt out and enqueue immediately (legacy instant event behaviour).

Pending triggers are stored in `automation_change_triggers` and processed by background timers plus `run_automations.py` cron.

## Automatic Actions

The initial action library contains:

- `create_file_by_time`: create a file with configured topic, name, type, visibility, and default block contents.
- `archive_at_time`: archive a topic, file, block, or task at a configured time.
- `rotate_daily_main_file`: archive the current main-topic `Daily` file and create a fresh `Daily` text file every day at 00:00.
- `process_refresh`: for each process, locate plan/doc/tasks files by type order, call the smart process update AI action, and store a delta proposal. Companion links are staged on the configured trigger task for both schedule and task activations; finalize archives old files and recreates plan, empty documentation table, and tasks after user review.
- `process_documentation_input`: for each process, stage companion links when the rule runs on schedule or when the user unchecks the trigger task. Opening the companion task launches a process input dialog; saving writes `[date, text]` into the doc table (new row below any header) and appends the grade to a line graph. Missing doc table/graph blocks are created automatically. Skipping a process completes its companion link without writing.
- `process_recap_update`: when plan, documentation, or tasks change in a process topic, regenerate the recap (`overview` file): AI-written summary, date-grouped update table, and a snapshot of flagged tasks. Writes blocks in place (no proposal or review).
- `project_summary_update`: when plan, execution, documentation, or tasks change in a project topic, regenerate the overview from the project state and part structure. Writes directly to overview only (no proposal or review).
- `view_task_reset`: for each configured task view schedule, turn completed tasks back to active, record tasks that were already active as missed, write an archived report file under the real `Automations` topic, and create a pending acknowledgement shown when the user next opens that view.

### View task reset (`view_task_reset`)

- **Trigger:** schedule-only by default. One automation rule stores per-view schedules in `params.view_resets` so the general Automations dialog stays compact.
- **Timing:** `daily` is locked to `daily HH:MM`; `weekly` is locked to `weekly DAY HH:MM`; `monthly` is locked to `monthly PLACEMENT DAY HH:MM`; `quarterly` is locked to `quarterly INTERVAL PLACEMENT DAY HH:MM` where `INTERVAL` is `3` or `4`.
- **Queueing:** the rule's `next_run_at` is the earliest enabled view schedule. When due, the dispatcher enqueues one run per due view using `event_context.target_view`.
- **Run:** completed tasks in the target view are unchecked (`done` → `active`). Tasks that were already active are left unchanged and recorded as missed.
- **Report:** each run creates an archived `doc` file in the `Automations` topic with reset/missed task details.
- **Acknowledgement:** the run creates a pending `task_reset_acknowledgements` row; the frontend shows it once when opening the target view and marks it approved after the user confirms.

### Companion trigger tasks (`process_refresh`, `process_documentation_input`)

Automations with a companion flow share one trigger task configured in the Automations dialog (view + section):

- **By time (`schedule`)**: the rule runs on schedule, stages companion links on that task, and marks it active for the user to open.
- **By task (`task`)**: the same task is shown checked until the user unchecks it, which runs the automation and stages companions on that task.

Unchecking only dispatches the automation when `trigger_type=task`. Scheduled runs never require unchecking first.

### Process documentation input (`process_documentation_input`)

- **Trigger:** `trigger_type=schedule` or `trigger_type=task`. Both use the same configured companion task (view/section). Schedule runs stage companions at the configured time and marks the task active; task mode stages companions when the user unchecks that task.
- **Flow:** tapping the companion task opens the `process_documentation_input` dialog. The user enters daily text and a 1–10 grade per process, or skips. All processes share one trigger task in both activation modes.
- **Write API:** `POST /process_documentation_inputs` with `{ topic_id, text, grade, date?, timezone? }`.
- **Doc table:** inserts `[date, text]` as a new row below any header row. Storage order is date-first so RTL tables show date on the right in Hebrew.
- **Doc graph:** appends the date to `labels` and the grade to `values` on a line graph block, creating table/graph blocks when missing.
- **Processes without a doc file:** staged as skipped companions; the dialog shows a warning and the user can skip without writing.

### Event recap (`process_recap_update`)

- **Trigger:** `trigger_type=event` with `params.event=file_changed`. Matches changes to `plan`, `doc`, or `tasks` files (not recap itself). Uses the shared change-trigger debounce (30s idle, follow-up if dirty during run).
- **Run:** `smart_process_recap_update` in `services/ai_recap_actions.py` gathers previous summary, plan, documentation, and flagged tasks (`section_flag=important` on any view, scoped to the process). AI returns `summary_text` and merged `update_rows` by date; the action replaces recap blocks directly.
- **Latency:** fires after the idle window via a background timer; cron also processes overdue triggers.

### Project summary (`project_summary_update`)

- **Trigger:** `trigger_type=event` with `params.event=file_changed`. Matches project `plan`, `execution`, `doc`, and `tasks` files, excluding `overview` to avoid self-trigger loops.
- **Parts:** project parts are inner `header` blocks read from `plan`, `execution`, and `tasks`.
- **Current part:** AI infers the current main part from recent edits, docs, flagged tasks, and project content.
- **Run:** `smart_project_summary_update` gathers plan, execution, documentation, tasks, previous overview, and flagged tasks, then replaces overview blocks with current summary, current part focus, flagged current-part tasks, flagged other-part tasks, recent progress date table, and ordered part list.
- **Safety:** this automation only writes the `overview` file. Synchronizing project part headers across source files belongs to a separate future automation.

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

- Built-in definitions: `GET /automation_definitions`, `GET /automation_definitions/<key>`
- CRUD for rules is exposed through `/automation_rules`.
- Manual execution for testing is exposed through `POST /automation_rules/<id>/run` (returns `202` with a queued run and processes that run in a background thread).
- Run status is exposed through `GET /automation_runs/<id>` and `GET /automation_runs?status=queued,running`.
- View task reset acknowledgements are exposed through `GET /task_reset_acknowledgements?view_type=<view>&status=pending` and `POST /task_reset_acknowledgements/<id>/approve`.
- Process update finalize is exposed through `POST /ai_proposals/<id>/finalize`.
- AI proposals are exposed through `/ai_proposals` and approval/rejection endpoints.
- Archive is exposed through normal resource PATCH fields and by `include_archived=true` list query parameters.

## Migration

Apply [`migrations/007_automation_run_queue.sql`](../migrations/007_automation_run_queue.sql) before deploying queue support.
Apply [`migrations/012_task_reset_acknowledgements.sql`](../migrations/012_task_reset_acknowledgements.sql) before enabling view task reset acknowledgements.

## Add a new automation (checklist)

1. **Registry entry** — add `AutomationDefinition` in `services/automation_definitions.py` (scope, activations, bindings, optional companion + AI metadata).
2. **Action handler** — implement `run_action` branch in `services/automation_actions.py`; resolve files via `resolve_files_by_bindings`, not hardcoded types.
3. **AI (optional)** — add proposal types / finalize path in `services/ai_proposal_actions.py`.
4. **Companion (optional)** — configure `companion` in definition; ensure `create_companion_task` runs for topics in scope.
5. **Flutter flow (optional)** — register `companion.flow_key` in `lib/core/registry/automation_flow_registry.dart`.
6. **UI** — definition appears automatically via `GET /automation_definitions`; trigger segments and scope label come from definition metadata.
7. **Docs** — add a row to the built-in automations table above.
