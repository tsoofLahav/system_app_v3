# Area: Automations (frontend)

Backend twin: [`system_app_back_end/areas/automations/AREA.md`](../../../../system_app_back_end/areas/automations/AREA.md) — read it for the cron loop and the step vocabulary.

Saved AI actions are a **different thing** — see [production agent](../production_agent/AREA.md). They meet an automation only as one kind of step.

## Core rule

An automation is a **scope**, a **trigger**, and an ordered **series of steps**. Creating one is not the same as saving a prompt: the builder asks where it may look, when it fires, and what to do, in that order.

## What the user configures

| Field | UI |
|-------|-----|
| Name | Shown in the automations list |
| Scope | All topics / one topic / a topic type (`project`, `process`, `area`, `other`) |
| Schedule | Once a day / week / month, with structured time controls — never a cron string |
| Enabled | Off means it never fires automatically |
| Steps | An ordered list. Add, reorder, delete. |

A single-topic scope is also the target for a "create a file" step. Broader scope makes that step pick its own topic.

### Step kinds

| Kind | What the user fills in |
|------|------------------------|
| Run AI | A saved action, or a prompt written here, plus review / apply directly |
| Create a file | Name (`{date}` and friends move with the calendar); a topic if scope is not one topic |
| Unmark tasks | Every done task in scope goes back to active |
| Archive files | Everything in scope, or older than N days |

## Surfaces

| Surface | What it is for |
|---------|----------------|
| [`automation_dialog.dart`](automation_dialog.dart) (bottom bar) | The automations list: create, edit, run now, delete |
| [`automation_builder_dialog.dart`](automation_builder_dialog.dart) | The one editor — create and rewrite |
| Agent dialog / AI bar ⋯ | Saved **actions**, not automations |

Timing uses locked structured controls rather than free text, so an invalid schedule string cannot be produced. Daily picks a time; weekly picks a day and time; monthly picks a placement (first / second / third / last), a weekday, and a time. The string sent is `daily 08:00`, never `0 8 * * *`.

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
- A disabled automation must not appear as active.
- Refresh the current topic after a run completes — otherwise the user sees stale content.
- Do not put automations on the AI bar. That bar is for actions you press while looking at something.
