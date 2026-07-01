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

## Automation definitions (registry)

Built-in automations are defined in code at `services/automation_definitions.py`. Each **definition** is the source of truth for scope, file bindings, allowed activations, companion flow, and related AI actions. A user's `automation_rules` row is an **instance**: enabled flag, schedule, timezone, trigger placement, and companion view/section overrides.

**v1 constraints:**

- The **frontend** only shows activations and scope described in each definition.
- **PATCH accepts full `params`** (including echoed `scope`/`bindings` from GET). Missing keys are filled from definition defaults on save.
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
| `weekly_process_refresh` | All `process` topics | `schedule`, `task`, `manual` | `plan`, `doc`, `tasks` | `process_update_review` in daily / Process updates | `smart_process_update` → `process_smart_update`, `process_refresh_skipped`; review `plan` + `tasks` |

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
| `event` | Backend dispatches after matching domain events (v1: `file_changed`; not exposed in UI yet) |
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

- Built-in definitions: `GET /automation_definitions`, `GET /automation_definitions/<key>`
- CRUD for rules is exposed through `/automation_rules`.
- Manual execution for testing is exposed through `POST /automation_rules/<id>/run` (returns `202` with a queued run and processes that run in a background thread).
- Run status is exposed through `GET /automation_runs/<id>` and `GET /automation_runs?status=queued,running`.
- Process update finalize is exposed through `POST /ai_proposals/<id>/finalize`.
- AI proposals are exposed through `/ai_proposals` and approval/rejection endpoints.
- Archive is exposed through normal resource PATCH fields and by `include_archived=true` list query parameters.

## Migration

Apply [`migrations/007_automation_run_queue.sql`](../migrations/007_automation_run_queue.sql) before deploying queue support.

## Add a new automation (checklist)

1. **Registry entry** — add `AutomationDefinition` in `services/automation_definitions.py` (scope, activations, bindings, optional companion + AI metadata).
2. **Action handler** — implement `run_action` branch in `services/automation_actions.py`; resolve files via `resolve_files_by_bindings`, not hardcoded types.
3. **AI (optional)** — add proposal types / finalize path in `services/ai_proposal_actions.py`.
4. **Companion (optional)** — configure `companion` in definition; ensure `create_companion_task` runs for topics in scope.
5. **Flutter flow (optional)** — register `companion.flow_key` in `lib/core/registry/automation_flow_registry.dart`.
6. **UI** — definition appears automatically via `GET /automation_definitions`; trigger segments and scope label come from definition metadata.
7. **Docs** — add a row to the built-in automations table above.
