# Area: Automations (frontend)

Backend twin: [`system_app_back_end/areas/automations/AREA.md`](../../../../system_app_back_end/areas/automations/AREA.md) — read it for the cron loop and the step vocabulary.

Saved AI actions are a **different thing** — see [production agent](../production_agent/AREA.md). They meet an automation only as one kind of step.

## Core rule

An automation is a **scope**, a **trigger**, and an ordered **series of steps**. Creating one is not the same as saving a prompt: the builder asks where it may look, when it fires, and what to do, in that order.

## What the user configures

| Field | UI |
|-------|-----|
| Name | Shown in the automations list |
| Scope | All topics / one topic / a topic type (loaded from `topic_types`) |
| Schedule | Once a day / week / month. Weekly and monthly use a calendar next to a matching 24-hour numbered dial (typed hour and minute under the dial); daily is the clock alone |
| Enabled | Switch on the **end** of each automations-list row (after edit, run, delete) — off means it never fires automatically |
| Steps | Horizontal frames. Add from `+`, tap a frame to edit. |

A single-topic scope is also the target for a "create a file" step. Broader scope makes that step pick its own topic, except a type-scoped step with a **template slot**, which copies that empty file into every topic of the type.

### Step kinds

| Kind | What the user fills in |
|------|------------------------|
| Run AI | A saved action, or a prompt written here, plus review / apply directly |
| Create a file | A template slot when the scope is a typed template, or a name (`{date}` and friends); a topic if scope is not one topic and not a slot |
| Unmark tasks | Every done task in scope goes back to active |
| Archive files | Everything in scope, older than N days, or one template slot |

## Surfaces

| Surface | What it is for |
|---------|----------------|
| [`automation_dialog.dart`](automation_dialog.dart) (bottom bar) | The automations list: create, edit, run now, delete, on/off |
| [`automation_builder_dialog.dart`](automation_builder_dialog.dart) | The one editor — create and rewrite |
| Agent dialog / AI bar ⋯ | Saved **actions**, not automations |

Timing uses locked structured controls rather than free text, so an invalid schedule string cannot be produced. The builder is three framed sections: details (name, scope, daily/weekly/monthly), when (a compact calendar beside a matching 24-hour numbered dial with typed hour and minute, both in this dialog), and steps (a horizontal strip of frames). Frequency stays in details. Weekly marks that weekday every week; monthly infers first / second / third / last from the tapped date (a fourth-of-five that is not the last maps to third). Flip months to see where it falls later. Daily shows only the clock. `+` under the strip adds a new AI action (the regular create dialog), a saved AI action, or a system step. Tap a frame to edit it. Enabled is a switch on the automations **list** (outermost after edit / run / delete), not in the builder. Create sits under the list. The string sent is `daily 08:00`, never `0 8 * * *`.

## Running

| Trigger | Path |
|---------|------|
| **Run now** | `POST /automations/:id/run` — the stored scope, same as the clock |
| **Schedule** | Server cron; `next_run_at` is the next fire |

Results: each AI step goes through `presentAgentRunResult`; other steps snackbar their summaries. The open topic reloads so a new or archived file appears.

| File | Role |
|------|------|
| [`automation_dialog.dart`](automation_dialog.dart) | List and run |
| [`automation_builder_dialog.dart`](automation_builder_dialog.dart) | Scope, schedule, steps |
| [`schedule_format.dart`](schedule_format.dart) | DSL parse / format |
| [`automation_service.dart`](automation_service.dart) | Automations API |
| [`automation.dart`](automation.dart) | Model, scope kinds, step kinds |

## Rules

- Never build a schedule string by hand; use the structured controls.
- Scope is required.
- A disabled automation must not appear as active. The on/off switch lives on the list and PATCHes `enabled` only.
- Refresh the current topic after a run completes — otherwise the user sees stale content.
- Do not put automations on the AI bar. That bar is for actions you press while looking at something.
