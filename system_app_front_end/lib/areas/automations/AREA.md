# Area: Automations (frontend)

Backend twin: [`system_app_back_end/areas/automations/AREA.md`](../../../../system_app_back_end/areas/automations/AREA.md) — read it for the cron loop and the step vocabulary.

Saved AI actions are a **different thing** — see [production agent](../production_agent/AREA.md). They meet an automation only as one kind of step.

## Core rule

An automation is a **scope**, a **trigger**, and an ordered **series of steps**. Creating one is not the same as saving a prompt: the builder asks where it may look, when it fires, and what to do, in that order.

## What the user configures

| Field | UI |
|-------|-----|
| Name | English and Hebrew, both required; the list follows the UI language |
| Scope | All topics / one topic / a topic type (loaded from `topic_types`) |
| Schedule | Once a day / week / month. Weekly and monthly use a calendar next to a matching 24-hour numbered dial (typed hour and minute under the dial); daily is the clock alone |
| Enabled | Switch on the **end** of each automations-list row (after edit, run, delete) — off means it never fires automatically |
| Steps | Horizontal frames. Drag to reorder (run order is the array order). Add from `+`, tap a frame to edit. Delete a step with the small x on the frame — the step editor has no trash. |

A single-topic scope is also the target for a "create a file" step. Broader scope makes that step pick its own topic, except a type-scoped step with a **template slot**, which copies that empty file into every topic of the type.

### Step kinds

| Kind | What the user fills in |
|------|------------------------|
| Run AI | A saved action, or a prompt written here, plus review / apply directly |
| Create a file | A template slot when the scope is a typed template, or a name (`{date}` and friends); a topic if scope is not one topic and not a slot |
| Unmark tasks | Every done task in scope goes back to active |
| Archive files | Everything in scope, older than N days, one file in a topic, or one template slot |
| Add to a file | Saved snippet (real file editor) appended onto a chosen topic file or a template slot |

## Surfaces

| Surface | What it is for |
|---------|----------------|
| [`automation_dialog.dart`](automation_dialog.dart) (bottom bar) | Two lists: regular automations and **section windows**. Regular: create, edit, run now, delete, on/off. Section windows are auto-created with a view section (off until start + duration are set); edit opens the window editor, no delete |
| [`automation_builder_dialog.dart`](automation_builder_dialog.dart) | Regular automations — create and rewrite |
| [`section_window_editor.dart`](section_window_editor.dart) | Start time + duration for a section window |
| Agent dialog / AI bar ⋯ | Saved **actions**, not automations |

## Section windows and complimentary tasks

Every named view section gets a `section_window` automation (created off). Start + duration open a window: attention dots on the **sidebar view** and **section header** until the section is fully done or the duration ends. If active leftovers remain at the end, a blocking confirm (any screen) recycles **routine** done tasks and archives leftover **one-time** tasks.

A regular automation whose AI steps need **user input** or **review** must pick a **routine** view + section. Its clock is a read-only copy of that section window. If the window is off, it does not fire on the clock. On save it places **only the complimentary tasks those steps need**:

| Role | When | EN | HE |
|------|------|----|----|
| Input | an AI step `requires_user_input` | `{name} automation task` | `{name} משימת אוטומציה` |
| Review | an AI step `apply_mode` is review | `{name} review task` | `{name} משימת סקירה` |

Press the **title** to open the input or review dialog. The pipeline still marks the row when input is submitted or review finishes. The checkbox works like any other task: mark it to give up that round, unmark to take it back. Input is clickable until submitted; then hover “user input was already received”. Review stays silent and unclickable until a pending review exists — only then hover “review is in process”. Both recycle at the next section start.

When input covers several topics, the dialog shows **one topic at a time**. The header uses that topic’s colour ombre (same veil as the topic page). Template topics are never in automation or AI-action scope.

The section-window duration is **hours** and **minutes**, each labelled above the field (not as a disappearing hint).

Timing uses locked structured controls rather than free text, so an invalid schedule string cannot be produced. The builder is three framed sections: details (name, scope, daily/weekly/monthly), when (a compact calendar beside a matching 24-hour numbered dial with typed hour and minute, both in this dialog), and steps (a horizontal strip of frames; long-press drag reorders them — the run walks that array in order). Frequency stays in details. Weekly marks that weekday every week; monthly infers first / second / third / last from the tapped date (a fourth-of-five that is not the last maps to third). Flip months to see where it falls later. Daily shows only the clock. `+` under the strip adds a new AI action (the regular create dialog), a saved AI action, or a system step. Choosing **Add to a file** opens the real file editor on a scratch file; Save stores that snippet on the step (appended onto the target at run). Tap a frame to edit it. Remove a step with the corner x on its frame, not from inside the step editor. Enabled is a switch on the automations **list** (outermost after edit / run / delete), not in the builder. Create sits under the list. The string sent is `daily 08:00`, never `0 8 * * *`.

## Running

| Trigger | Path |
|---------|------|
| **Run now** | `POST /automations/:id/run` — the stored scope, same as the clock |
| **Schedule** | Server cron; `next_run_at` is the next fire |

Results: each AI step goes through `presentAgentRunResult`; other steps snackbar their summaries. The open topic reloads so a new or archived file appears. Cancel on the AI spinner drops those results the same way a cancelled consult does.

| File | Role |
|------|------|
| [`automation_dialog.dart`](automation_dialog.dart) | Regular + section-window lists |
| [`automation_builder_dialog.dart`](automation_builder_dialog.dart) | Scope, schedule, steps, complimentary section |
| [`section_window_editor.dart`](section_window_editor.dart) | Section window start + duration |
| [`complimentary_input_dialog.dart`](complimentary_input_dialog.dart) | Per-topic (or one) user input, then run |
| [`leftover_clear_dialog.dart`](leftover_clear_dialog.dart) | Blocking leftover confirm |
| [`fill_file_snippet_dialog.dart`](fill_file_snippet_dialog.dart) | Real file editor for a `fill_file` snippet |
| [`schedule_format.dart`](schedule_format.dart) | DSL parse / format |
| [`automation_service.dart`](automation_service.dart) | Automations API |
| [`automation.dart`](automation.dart) | Model, scope kinds, step kinds |

## Rules

- Never build a schedule string by hand; use the structured controls.
- Scope is required.
- A disabled automation must not appear as active. The on/off switch lives on the list and PATCHes `enabled` only.
- Refresh the current topic after a run completes — otherwise the user sees stale content.
- Do not put automations on the AI bar. That bar is for actions you press while looking at something.
