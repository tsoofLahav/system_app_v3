# Area: Automations (backend)

Frontend counterpart: [`system_app_front_end/lib/areas/automations/AREA.md`](../../../system_app_front_end/lib/areas/automations/AREA.md).

Saved AI actions are a **different thing** — they live at [`/ai-actions`](../production_agent/AREA.md). They meet an automation only as one kind of step.

## Core rule

An automation is a **scope**, a **trigger**, and an ordered **series of steps**. It adds no new AI logic: an `ai` step hands a prompt to the same [production agent](../production_agent/AREA.md) pipeline a typed prompt uses. The other steps are ordinary app operations, callable without a request.

## Configuration

Row in `automations` (migration [`011_ai_actions_split.sql`](../../migrations/011_ai_actions_split.sql) moved the old button-rows out):

| Field | Meaning |
|-------|---------|
| `name`, `name_he` | Shown in the automations dialog; UI language picks which |
| `scope` | `{"kind": "all"}` / `{"kind": "topic", "topic_id"}` / `{"kind": "topic_type", "topic_type_id"}`. One-release fallback still reads `"tag": "process"`. Legacy `{topic_ids, file_ids}` still resolves. Template topics (`is_template`) are never in scope. |
| `trigger` | `{"type": "schedule"}` today. Event types are stored but not dispatched. |
| `steps` | `[{ "kind": …, …params }]` — the work, in order |
| `schedule` | `daily HH:MM`, `weekly DAY HH:MM`, `monthly PLACEMENT DAY HH:MM`, or `monthly N PLACEMENT DAY HH:MM` (every N months, 2–12). Legacy `quarterly N …` still parses. |
| `timezone` | Schedule is interpreted here, stored UTC. Default for new rows from the app: `Asia/Jerusalem`. |
| `enabled` | Disabled automations never fire automatically |
| `last_run_at`, `next_run_at` | Scheduling bookkeeping |
| `kind` | `standard` (default) or `section_window` |
| `view_id`, `section_key` | Section window target, or complimentary placement for a standard automation |
| `window_duration_minutes` | How long after start a section window stays open |
| `window_opened_at`, `window_closes_at`, `pending_clear` | Open window + leftover confirm payload |

A **section window** has no steps. The minute cron opens it at the start, recycles complimentary / routine tasks, and at duration end **unmarks** the section if nothing is still active. Only missed tasks write `pending_clear` and wait for confirm. Saving a new start or duration on an open window calls `clear_section_window_state` (unmark, drop the dot). Standard automations locked to a section copy that schedule and **do not fire on their own clock** if the window is off. If they need user input they wait for `POST /automations/:id/submit-input`; if they only need review they run at section start. Complimentary tasks are created **only for the roles the steps need** — input when `requires_user_input`, review when `apply_mode` is review — never a spare review row on an input-only automation. `GET /automations` prunes leftover roles. List payload includes `has_pending_review` so the review hover is silent until a pending review exists.

Complimentary notes are **full text**, not `hints.selected_text`. `store_user_input` keeps each topic's note (newlines included) up to `COMPLIMENTARY_INPUT_MAX_CHARS` (12 000); over that is HTTP 400 with a stated limit, never a silent clip. `format_user_input_for_prompt` turns each topic into a delimited block (`--- user input · {name} ---`) so a long paragraph stays attributed to that topic when it is appended onto the AI-step prompt.

A single-topic scope is also the **target**: a step that has to put something somewhere (create a file) uses it. Broader scope leaves the step to carry its own `topic_id`, except `create_file` with `template_slot`, which skeleton-clones that slot into **each** topic in a type scope.

## Steps

| Kind | What it does |
|------|----------------|
| `ai` | Run a prompt, either inline or from a saved `action_id`. Each step has its own `apply_mode`. |
| `create_file` | Create a file. `{date}` `{weekday}` `{month}` `{year}` in the name move with the calendar. With `template_slot`, copy that empty shell from the type template into every topic in scope. |
| `unmark_tasks` | Send done tasks in scope (or one `task_list_id`) back to active. |
| `archive_files` | Soft-archive files in scope; optional `older_than_days`, `file_ids`, or `template_slot`. |
| `fill_file` | Append saved snippet content onto matching live files. Target is `file_id` (one topic file) or `template_slot` (that named file in every topic of a type). Payload is `document_json` plus cloned `objects`. |
| `bring_file` | Project one live file from the scope onto Home (`file_id`). Same file, still owned by its topic. Membership is `workspaces.home_visit_file_ids`. |

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
  → activate pending tasks whose date has arrived (Asia/Jerusalem)
  → load enabled automations that have a schedule
  → plan_tick: arm (first sight), run (due), or skip
  → run_automation → walk steps → automation_runs row
  → write last_run_at, next_run_at, finished_at
```

A new `daily 08:00` saved at 10:00 is **armed**, not run — "daily at eight" means the next eight. Saved *during* the 08:00 minute, it runs that minute; otherwise a 08:00:04 first sight jumps to tomorrow and today never fires. `POST /automations/:id/run` does the same walk with `trigger_source=manual`, on the stored scope (this is a background job, not a button pressed while looking at something).

## Run history

`automation_runs` stores every execution: status, trigger source, per-step result, error, timestamps.

## Modules

| Module | Role |
|--------|------|
| [`routes/automations.py`](routes/automations.py) | CRUD + run, submit-input, pending-clears, clear-leftovers, review-status |
| [`services/section_windows.py`](services/section_windows.py) | Auto-create/backfill windows, leftover clear, complimentary tasks |
| [`services/steps.py`](services/steps.py) | Step vocabulary and save-time validation |
| [`services/scope.py`](services/scope.py) | Kind → `{workspace_id, topic_ids, file_ids}` |
| [`services/run_automation.py`](services/run_automation.py) | Walk the series, record the run |
| [`services/actions/`](services/actions/) | `ai`, `create_file`, `unmark_tasks`, `archive_files`, `fill_file`, `bring_file` |
| [`services/automation_schedule.py`](services/automation_schedule.py) | `next_run_after()` / `plan_tick()` |
| [`../../scripts/run_automations.py`](../../scripts/run_automations.py) | Cron entry point |

File and task mutations used by the actions live next to their HTTP routes: [`areas/files/services/file_ops.py`](../files/services/file_ops.py), [`areas/objects/services/task_ops.py`](../objects/services/task_ops.py) (including daily pending → active).

## Rules

- Disabled automations must not run automatically; manual run stays allowed.
- Schedules are stored as strings and resolved in the automation's timezone — never assume UTC input.
- `plan_tick` compares naive UTC. Postgres may return `next_run_at` timezone-aware; strip that before comparing, or the cron dies. The same strip (`as_utc_naive`) applies to `window_opened_at` / `window_closes_at` — listing automations calls `window_is_open`, so a mixed-aware compare 500s the whole list.
- Cron prints one line per automation every minute (`skip` / `arm` / `run`) to stdout, so Render logs show the decision. `logger.info` alone is silent there.
- The cron process must have `OPENAI_API_KEY` as an **environment variable** on that Cron Job (Secret Files are not `os.environ`). Each tick logs `openai_key=yes/no` and the `OPENAI*` env names, never the secret.
- Never send a cron line; the parser only reads the DSL above (`daily` / `weekly` / `monthly`, including `monthly N` for every N months).
- Automations must respect `scope` the same way agent tools do (`file_allowed` after resolve).
- An `ai` step's `apply_mode` is its own. `review` produces proposals; it must not write files directly.

## Known gaps

Event triggers (`file.updated`, `task.unmarked`, another automation finished) are not dispatched. Phase two: an `automation_events` queue drained by the same minute cron.
