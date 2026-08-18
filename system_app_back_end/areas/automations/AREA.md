# Area: Automations (backend)

Frontend counterpart: [`system_app_front_end/lib/areas/automations/AREA.md`](../../../system_app_front_end/lib/areas/automations/AREA.md).

Saved AI actions are a **different thing** — they live at [`/ai-actions`](../production_agent/AREA.md). They meet an automation only as one kind of step.

## Core rule

An automation is a **scope**, a **trigger**, and an ordered **series of steps**. It adds no new AI logic: an `ai` step hands a prompt to the same [production agent](../production_agent/AREA.md) pipeline a typed prompt uses. The other steps are ordinary app operations, callable without a request.

## Configuration

Row in `automations` (migration [`011_ai_actions_split.sql`](../../migrations/011_ai_actions_split.sql) moved the old button-rows out):

| Field | Meaning |
|-------|---------|
| `name` | Shown in the automations dialog |
| `scope` | `{"kind": "all"}` / `{"kind": "topic", "topic_id"}` / `{"kind": "topic_type", "tag"}`. Legacy `{topic_ids, file_ids}` still resolves. |
| `trigger` | `{"type": "schedule"}` today. Event types are stored but not dispatched. |
| `steps` | `[{ "kind": …, …params }]` — the work, in order |
| `schedule` | `daily HH:MM`, `weekly DAY HH:MM`, `monthly PLACEMENT DAY HH:MM` |
| `timezone` | Schedule is interpreted here, stored UTC. Default for new rows from the app: `Asia/Jerusalem`. |
| `enabled` | Disabled automations never fire automatically |
| `last_run_at`, `next_run_at` | Scheduling bookkeeping |

A single-topic scope is also the **target**: a step that has to put something somewhere (create a file) uses it. Broader scope leaves the step to carry its own `topic_id`.

## Steps

| Kind | What it does |
|------|----------------|
| `ai` | Run a prompt, either inline or from a saved `action_id`. Each step has its own `apply_mode`. |
| `create_file` | Create a file. `{date}` `{weekday}` `{month}` `{year}` in the name move with the calendar. |
| `unmark_tasks` | Send done tasks in scope (or one `task_list_id`) back to active. |
| `archive_files` | Soft-archive files in scope; optional `older_than_days` or `file_ids`. |

Adding a kind is an entry in [`services/steps.py`](services/steps.py) `STEP_SPECS` and a function in [`services/actions/`](services/actions/). Validation refuses a bad series when it is saved, not at 2am when it fires. Steps stop at the first error; earlier ones stand.

## Cron job on the server

Render runs a **Cron Job service** separate from the web service:

| Setting | Value |
|---------|-------|
| Schedule | `*/1 * * * *` (every minute) |
| Command | `cd system_app_back_end && python scripts/run_automations.py` |
| Database | Same `DATABASE_URL` as the web service |

```
every minute
  → load enabled automations that have a schedule
  → plan_tick: arm (first sight), run (due), or skip
  → run_automation → walk steps → automation_runs row
  → write last_run_at, next_run_at, finished_at
```

A new `daily 08:00` saved at 10:00 is **armed**, not run — "daily at eight" means the next eight. `POST /automations/:id/run` does the same walk with `trigger_source=manual`, on the stored scope (this is a background job, not a button pressed while looking at something).

## Run history

`automation_runs` stores every execution: status, trigger source, per-step result, error, timestamps.

## Modules

| Module | Role |
|--------|------|
| [`routes/automations.py`](routes/automations.py) | CRUD + `POST /automations/:id/run` |
| [`services/steps.py`](services/steps.py) | Step vocabulary and save-time validation |
| [`services/scope.py`](services/scope.py) | Kind → `{workspace_id, topic_ids, file_ids}` |
| [`services/run_automation.py`](services/run_automation.py) | Walk the series, record the run |
| [`services/actions/`](services/actions/) | `ai`, `create_file`, `unmark_tasks`, `archive_files` |
| [`services/automation_schedule.py`](services/automation_schedule.py) | `next_run_after()` / `plan_tick()` |
| [`../../scripts/run_automations.py`](../../scripts/run_automations.py) | Cron entry point |

File and task mutations used by the actions live next to their HTTP routes: [`areas/files/services/file_ops.py`](../files/services/file_ops.py), [`areas/objects/services/task_ops.py`](../objects/services/task_ops.py).

## Rules

- Disabled automations must not run automatically; manual run stays allowed.
- Schedules are stored as strings and resolved in the automation's timezone — never assume UTC input.
- `plan_tick` compares naive UTC. Postgres may return `next_run_at` timezone-aware; strip that before comparing, or the cron dies.
- Never send a cron line; the parser only reads the DSL above.
- Automations must respect `scope` the same way agent tools do (`file_allowed` after resolve).
- An `ai` step's `apply_mode` is its own. `review` produces proposals; it must not write files directly.

## Known gaps

Event triggers (`file.updated`, `task.unmarked`, another automation finished) are not dispatched. Phase two: an `automation_events` queue drained by the same minute cron.
