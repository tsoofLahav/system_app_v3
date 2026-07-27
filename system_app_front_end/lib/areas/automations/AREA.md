# Area: Automations (frontend)

Backend twin: [`system_app_back_end/areas/automations/AREA.md`](../../../../system_app_back_end/areas/automations/AREA.md) — read it for the cron loop and config fields.

## Core rule

An automation is a **saved AI run**. Creating one is the same act as typing a prompt, except it is stored and can fire on a schedule or from the AI actions menu.

## What the user configures

| Field | UI |
|-------|-----|
| Name | Shown in the automations list and the AI actions menu |
| Prompt | The instruction sent to the agent |
| Scope | Which topic or files it may touch |
| Apply mode | `direct_apply` writes, `review` proposes, `notify_only` reports |
| Schedule | Once a day / week / month, with structured time controls |
| Enabled | Off means it never fires automatically |

Timing uses locked structured controls rather than free text, so an invalid schedule string cannot be produced. Daily picks a time; weekly picks a day and time; monthly picks a placement (first / second / third / last), a weekday, and a time.

## Running

| Trigger | Path |
|---------|------|
| **Run now** | `POST /automations/:id/run` — enqueues, shows “started”, polls run status |
| **Schedule** | Server cron; the app finds out by polling runs |
| **AI actions menu** | Manual automations appear in the bolt menu — see [production agent](../production_agent/AREA.md) |

Run now is **non-blocking**. The app does not sit on the request; it polls `automation_runs` and refreshes the open topic or view when a run completes so new or archived files appear.

Automations with `apply_mode: 'review'` surface their result through the same diff dialog as a manual run.

| File | Role |
|------|------|
| [`automation_dialog.dart`](automation_dialog.dart) | Create and edit automations |
| [`automation_abandon_dialog.dart`](automation_abandon_dialog.dart) | Confirm discarding edits |
| [`automation_service.dart`](automation_service.dart) | Automations API |
| [`automation.dart`](automation.dart), [`automation_run.dart`](automation_run.dart) | Models |

## Rules

- Never block the UI on a run; enqueue and poll.
- A disabled automation must not appear as active anywhere, including the AI actions menu.
- Refresh the current topic or view after a run completes — otherwise the user sees stale content.
- Scope is required, same as a manual agent run.
- Never build a schedule string by hand; use the structured controls.

## Legacy models

`automation_rule.dart`, `automation_definition.dart`, and `automation_companion_link.dart` are v1 shapes still present in the tree. New work should use `automation.dart`.
