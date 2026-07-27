# Area: Automations (backend)

Automations are saved agent runs that fire on a schedule instead of a button press. Frontend counterpart: [`system_app_front_end/lib/areas/automations/AREA.md`](../../../system_app_front_end/lib/areas/automations/AREA.md).

## Core rule

An automation adds **no new AI logic**. It stores a prompt plus a scope and hands them to the same [production agent](../production_agent/AREA.md) pipeline a manual run uses.

## Configuration

Row in `automations`:

| Field | Meaning |
|-------|---------|
| `name` | Shown in the automations menu |
| `prompt` | The task text sent to the agent |
| `scope` | `{ "topic_ids": [...] }` / `{ "file_ids": [...] }` — what it may touch |
| `apply_mode` | `direct_apply`, `review`, or `notify_only` |
| `schedule` | `daily HH:MM`, `weekly DAY HH:MM`, `monthly PLACEMENT DAY HH:MM`, `quarterly INTERVAL PLACEMENT DAY HH:MM` |
| `timezone` | Schedule is interpreted in this zone, stored UTC |
| `trigger` | JSONB — reserved for event triggers |
| `enabled` | Disabled automations never fire automatically |
| `last_run_at`, `next_run_at` | Scheduling bookkeeping |

## Cron job on the server

Render runs a **Cron Job service** separate from the web service:

| Setting | Value |
|---------|-------|
| Schedule | `*/1 * * * *` (every minute) |
| Command | `cd system_app_back_end && python scripts/run_automations.py` |
| Database | Same `DATABASE_URL` as the web service |

The script is deliberately dumb:

```
every minute
  → load enabled automations
  → for each: create automation_runs row (status=running, trigger_source=schedule)
  → run_agent(prompt, workspace_id, scope, apply_mode)
  → status = completed | failed, store result, commit
```

Manual runs (`POST /automations/:id/run`) do the same thing with `trigger_source=manual`, synchronously.

## Run history

`automation_runs` stores every execution: status, trigger source, full agent result, error, timestamps. The frontend polls this to report progress and surface proposals from `review` runs.

## Modules

| Module | Role |
|--------|------|
| [`routes/automations.py`](routes/automations.py) | CRUD + `POST /automations/:id/run` |
| [`services/automation_schedule.py`](services/automation_schedule.py) | `next_run_after()` — schedule string → next UTC datetime |
| [`../../scripts/run_automations.py`](../../scripts/run_automations.py) | Cron entry point |

## Rules

- Disabled automations must not run automatically; manual run stays allowed.
- A disabled automation whose run was already queued should be skipped, not executed.
- Schedules are stored as strings and resolved in the automation's timezone — never assume UTC input.
- Automations must respect `scope` exactly like manual runs.
- `review` automations produce proposals; they must not write files directly.

## Known gaps

Only schedule triggers are wired. `trigger` (event-based, e.g. "file changed") is stored but not dispatched. Scheduling currently runs every enabled automation each minute rather than consulting `next_run_at` — `next_run_after()` exists but is not yet used by the cron script.
