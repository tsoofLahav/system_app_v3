# Area: Automations (frontend)

Backend twin: [`system_app_back_end/areas/automations/AREA.md`](../../../../system_app_back_end/areas/automations/AREA.md) — read it for the cron loop and config fields.

## Core rule

An automation is a **saved AI run**. Creating one is the same act as typing a prompt, except it is stored and can fire on a schedule or from the AI actions menu.

Without a schedule it is a **saved AI action** — the same record, fired by hand. That is why the create form, the actions menu and the AI bar all read one list.

## What the user configures

| Field | UI |
|-------|-----|
| Name | Shown in the automations list, the actions menu, and on hover over its bar button |
| Prompt | The instruction sent to the agent |
| Scope | Which topic or files it may touch |
| Apply mode | `direct_apply` writes, `review` proposes, `notify_only` reports — create-form default is `defaultAutomationApplyMode` (must match backend `DEFAULT_AUTOMATION_APPLY_MODE`) |
| Icon | One of the curated keys in [`action_icons.dart`](../ui/action_icons.dart), picked from a grid |
| On the bar | An action can take one of six seats; the pin in its row puts it on or takes it off |
| Schedule | Once a day / week / month, with structured time controls |
| Enabled | Off means it never fires automatically |

Only actions get an icon that matters and a seat — a scheduled automation is never on the bar, because there is no one to press it.

## Three surfaces, one record

| Surface | What it is for |
|---------|----------------|
| Agent dialog | Where an action is **born** — see [production agent](../production_agent/AREA.md) |
| [`ai_actions_dialog.dart`](ai_actions_dialog.dart) (⋯ on the AI bar) | The saved actions and nothing else: pin, edit, run, delete. No create form, no schedules. |
| [`automation_dialog.dart`](automation_dialog.dart) (bottom bar) | Automations, with the actions tab alongside for completeness |

Editing anything goes through one editor, [`automation_edit_dialog.dart`](automation_edit_dialog.dart): name, prompt and apply mode for both kinds, a schedule field for the scheduled ones, an icon and a seat for the actions. Deleting asks first. A seat change is only sent when the user actually moves it, so saving a rename never shuffles the bar.

Timing uses locked structured controls rather than free text, so an invalid schedule string cannot be produced. Daily picks a time; weekly picks a day and time; monthly picks a placement (first / second / third / last), a weekday, and a time.

## Running

| Trigger | Path |
|---------|------|
| **Run now** | `POST /automations/:id/run` — enqueues, shows “started”, polls run status |
| **Schedule** | Server cron; the app finds out by polling runs |
| **AI bar** | Pinned actions are their own button; the rest run from the ⋯ dialog — see [production agent](../production_agent/AREA.md) |

A run started from the app sends the live scope and hints, not the stored scope: the user pressed it while looking at something. Only the cron falls back to what was saved.

Run now is **non-blocking**. The app does not sit on the request; it polls `automation_runs` and refreshes the open topic or view when a run completes so new or archived files appear.

Results go through `presentAgentRunResult` (production agent area) — review proposals open the diff dialog; applied runs snackbar + reload.

| File | Role |
|------|------|
| [`automation_dialog.dart`](automation_dialog.dart) | Create automations and actions, list both |
| [`ai_actions_dialog.dart`](ai_actions_dialog.dart) | The saved actions, from the ⋯ on the AI bar |
| [`automation_edit_dialog.dart`](automation_edit_dialog.dart) | The one editor for either kind |
| [`automation_abandon_dialog.dart`](automation_abandon_dialog.dart) | Confirm discarding edits |
| [`automation_service.dart`](automation_service.dart) | Automations API |
| [`automation.dart`](automation.dart), [`automation_run.dart`](automation_run.dart) | Models |

## Rules

- Never block the UI on a run; enqueue and poll.
- A disabled automation must not appear as active anywhere, including the AI actions menu.
- Refresh the current topic or view after a run completes — otherwise the user sees stale content.
- Scope is required, same as a manual agent run.
- Never build a schedule string by hand; use the structured controls.
- The bar holds six actions at most; when it is full, say so instead of silently dropping someone's seat.
- Store the icon **key**, never an `IconData` — the vocabulary must stay ours to change.

## Legacy models

`automation_rule.dart`, `automation_definition.dart`, and `automation_companion_link.dart` are v1 shapes still present in the tree. New work should use `automation.dart`.
