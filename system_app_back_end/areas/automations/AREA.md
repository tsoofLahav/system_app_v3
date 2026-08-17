# Area: Automations (backend)

Automations are saved agent runs that fire on a schedule instead of a button press. Frontend counterpart: [`system_app_front_end/lib/areas/automations/AREA.md`](../../../system_app_front_end/lib/areas/automations/AREA.md).

## Core rule

An automation adds **no new AI logic**. It stores a prompt plus a scope and hands them to the same [production agent](../production_agent/AREA.md) pipeline a manual run uses.

An automation with **no schedule** is a *saved AI action*: the same row, fired from a button instead of the clock. One table serves both, so an action becomes an automation by gaining a schedule and nothing else moves.

## Configuration

Row in `automations`:

| Field | Meaning |
|-------|---------|
| `name` | Shown in the automations menu |
| `prompt` | The task text sent to the agent |
| `scope` | `{ "topic_ids": [...] }` / `{ "file_ids": [...] }` — what it may touch |
| `apply_mode` | `direct_apply`, `review`, or `notify_only` — create/DB default from [`shared/run_config.py`](../../shared/run_config.py) (`DEFAULT_AUTOMATION_APPLY_MODE`) |
| `schedule` | `daily HH:MM`, `weekly DAY HH:MM`, `monthly PLACEMENT DAY HH:MM`, `quarterly INTERVAL PLACEMENT DAY HH:MM` |
| `timezone` | Schedule is interpreted in this zone, stored UTC |
| `trigger` | JSONB — `{"type": "manual"}` for an action, reserved otherwise for event triggers |
| `enabled` | Disabled automations never fire automatically |
| `icon` | Key into the frontend icon vocabulary — a name, never a code point |
| `bar_slot` | 1–6 = a seat on the AI bar (unique per workspace), NULL = actions menu only |
| `last_run_at`, `next_run_at` | Scheduling bookkeeping |

## Seats on the AI bar

Six slots, because that is what fits beside the other bottom-bar tools. Taking a
slot frees it on whoever held it — slot n is also keyboard shortcut n, so the
other five must not shuffle under the user's fingers. The rules live in
[`services/action_bar.py`](services/action_bar.py) as plain `{id: slot}` maps;
routes only read and write rows. Slots are cleared in their own flush before
being filled, since the unique index is checked per statement.

## A button runs on what is open

`POST /automations/:id/run` takes optional `scope` and `hints`. The bar sends
the topic, the open files, the focused file and the clock — the same context a
typed prompt sends — because the user pressed the button while looking at
something. The cron script sends neither and the stored `scope` applies.

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
| [`routes/automations.py`](routes/automations.py) | CRUD + `PUT /automations/bar-order` + `POST /automations/:id/run` |
| [`services/action_bar.py`](services/action_bar.py) | Slot rules and which scope a run uses |
| [`services/automation_schedule.py`](services/automation_schedule.py) | `next_run_after()` — schedule string → next UTC datetime |
| [`../../scripts/run_automations.py`](../../scripts/run_automations.py) | Cron entry point |

## Rules

- Disabled automations must not run automatically; manual run stays allowed.
- A disabled automation whose run was already queued should be skipped, not executed.
- Schedules are stored as strings and resolved in the automation's timezone — never assume UTC input.
- Automations must respect `scope` exactly like manual runs.
- `review` automations produce proposals; they must not write files directly.
- Never write `bar_slot` as a plain field update — go through the slot rules, or two actions end up in one seat.

## Known gaps

Only schedule triggers are wired. `trigger` (event-based, e.g. "file changed") is stored but not dispatched. Scheduling currently runs every enabled automation each minute rather than consulting `next_run_at` — `next_run_after()` exists but is not yet used by the cron script.
