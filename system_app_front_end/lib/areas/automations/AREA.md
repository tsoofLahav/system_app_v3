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
| Schedule | Once a day / week / month, a few times a week or month, or once every N months (2–12). Weekly, monthly, and every-N-months use a calendar next to a matching 24-hour numbered dial (typed hour and minute under the dial); daily is the clock alone. “A few times” taps toggle days; once-a-week / once-a-month replace. Every N months is counted from the month of the chosen day (`from YYYY-MM`), so the calendar and the clock skip the months in between. Times are **Israel** (`Asia/Jerusalem`), not UTC |
| Enabled | Switch on the **end** of each automations-list row (after edit, run, delete) — off means it never fires automatically |
| Steps | Horizontal frames. Drag to reorder (run order is the array order). Add from `+`, tap a frame to edit. Delete a step with the small x on the frame — the step editor has no trash. |

A single-topic scope is also the target for a "create a file" step. Broader scope makes that step pick its own topic, except a type-scoped step with a **template slot**, which copies that empty file into every topic of the type.

### Step kinds

| Kind | What the user fills in |
|------|------------------------|
| Run AI | A saved action, or a prompt written here, plus review / apply directly |
| Create a file | A template slot when the scope is a typed template, or a name (`{date}` and friends); a topic if scope is not one topic and not a slot |
| Unmark tasks | Every done task in scope goes back to active |
| Archive files | Everything in scope, older than N days, one **file name** in a topic, or one template slot. The picker lists existing names; the step stores the name, not an id |
| Add to a file | Saved snippet (real file editor, including insert of objects) appended onto a chosen **file name** or a template slot. At run the closest live name in scope wins (same resemblance as Connect-info search); nothing close enough errors |
| Project to Home | One **file name** from the scope visits Home (same file, still owned by its topic). Resolve like Add to a file |

## Surfaces

| Surface | What it is for |
|---------|----------------|
| [`automation_dialog.dart`](automation_dialog.dart) (bottom bar) | Two pages: regular automations and **section windows**, each searchable by name. Regular: create, edit, run now, delete, on/off. Section windows are auto-created with a view section (off until start + duration are set); edit opens the window editor, no delete |
| [`automation_builder_dialog.dart`](automation_builder_dialog.dart) | Regular automations — create and rewrite |
| [`section_window_editor.dart`](section_window_editor.dart) | Start time + duration for a section window |
| [`leftover_clear_dialog.dart`](leftover_clear_dialog.dart) | Blocking Report / Dismiss when a window ends with active tasks |
| Agent dialog / AI bar ⋯ | Saved **actions**, not automations |

## Section windows and complimentary tasks

Every named view section gets a `section_window` automation (created off). Start + duration open a window: attention dots on the **sidebar view** and **section header** until the last **active** task is marked done (the dot clears immediately, without waiting for the next poll) or the duration ends. When the duration ends with **nothing missed**, routine (and complimentary) tasks unmark immediately — no dialog. If any task is still **active**, a **blocking center modal** (any screen — not a snackbar; cannot dismiss without choosing) must be answered: **Report** appends what was missed and when onto a standing **Missed tasks** file on Home (`meta.system_kind = missed_section_report`, newest entry first), then leftover one-time tasks archive and the rest recycle; **Dismiss** means those leftovers were actually done or not needed — mark those same task rows done (do not archive-and-reinsert) and leave them done until the next window start. `GET /automations` closes expired windows so the 5s poll can raise the modal without waiting for the minute cron. Changing the window’s start or duration clears that cycle: all section tasks go active and the attention dot goes off.

A regular automation whose AI steps need **user input** or **review** must pick a **repeating** view + section. Its clock is a read-only copy of that section window. If the window is off, it does not fire on the clock. On save it places **only the complimentary tasks those steps need**:

| Role | When | EN | HE |
|------|------|----|----|
| Input | an AI step `requires_user_input` | `{name} automation task` | `{name} משימת אוטומציה` |
| Review | an AI step `apply_mode` is review | `{name} review task` | `{name} משימת סקירה` |

Press the **title** to open the input or review dialog. The title is pressable (dark-teal underline, same mark as connected text used to use) only **while the section window is open** and the row still needs work — input until submitted, review only when a pending review exists. Connected (description-linked) task text is the quieter mark: italic dark teal, and it keeps strikethrough when the task is done. The pipeline still marks the row when input is submitted or review finishes. The checkbox works like any other task: mark it to give up that round, unmark to take it back. Input hover after submit: “user input was already received”. Review stays silent until a pending review exists — only then hover “review is in process”. Both recycle at the next section start.

When input covers several topics, the dialog shows **one topic at a time**. **Enter** moves to the next topic (or Submit and run on the last). **⌘Enter** / Shift+Enter / Ctrl+Enter inserts a newline. Each note is full text sent with the automation prompt — not `hints.selected_text`. The field shows `{count} / {max}` against `complimentaryInputMaxChars` (12 000, same cap as the backend); over that, Next/Submit disable and the copy says to shorten the note. The dialog **closes immediately**; a small spinner sits next to the complimentary title while the run is in flight. The header uses a stronger topic-colour ombre than the topic page (`AppColors.topicDialogVeilAlpha`). Template topics are never in automation or AI-action scope.

The section-window duration is **hours** and **minutes**, each labelled above the field (not as a disappearing hint).

Timing uses locked structured controls rather than free text, so an invalid schedule string cannot be produced. The builder is three framed sections: details (name, scope, frequency chips), when (a compact calendar beside a matching 24-hour numbered dial with typed hour and minute, both in this dialog), and steps (a horizontal strip of frames; long-press drag reorders them — the run walks that array in order). Frequency stays in details. Weekly marks that weekday every week; a few times a week toggles several weekdays (`weekly mon,thu 09:00`). Monthly infers first / second / third / last from the tapped date (a fourth-of-five that is not the last maps to third); a few times a month toggles several of those slots (`monthly first.fri,third.mon 09:00`). Every N months uses that same day, then skips N−1 months from the month of the tap (`monthly 3 last fri 18:00 from 2026-08`). Flip months to see where it falls later — only cycle months are marked. Daily shows only the clock. `+` under the strip adds a new AI action (the regular create dialog), a saved AI action, or a system step. Choosing **Add to a file** opens the real file editor on a scratch file; the insert bar in that dialog adds objects the same way as a topic file. Save stores that snippet on the step (`document_json` plus cloned `objects`, appended onto the target at run). Tap a frame to edit it. Remove a step with the corner x on its frame, not from inside the step editor. Enabled is a switch on the automations **list** (outermost after edit / run / delete), not in the builder. Create sits under the regular list. The string sent is `daily 08:00`, never `0 8 * * *`.

## Running

| Trigger | Path |
|---------|------|
| **Run now** | `POST /automations/:id/run` — the stored scope, same as the clock |
| **Schedule** | Server cron in Asia/Jerusalem; `next_run_at` is the next fire (UTC instant) |

Results: each AI step goes through `presentAgentRunResult`; other steps snackbar their summaries. The open topic reloads so a new or archived file appears. Cancel on the AI spinner drops those results the same way a cancelled consult does.

| File | Role |
|------|------|
| [`automation_dialog.dart`](automation_dialog.dart) | Regular and section-window pages, each with name search |
| [`automation_builder_dialog.dart`](automation_builder_dialog.dart) | Scope, schedule, steps, complimentary section |
| [`section_window_editor.dart`](section_window_editor.dart) | Section window start + duration |
| [`complimentary_input_dialog.dart`](complimentary_input_dialog.dart) | Per-topic (or one) user input, then run |
| [`leftover_clear_dialog.dart`](leftover_clear_dialog.dart) | Blocking leftover Report / Dismiss |
| [`fill_file_snippet_dialog.dart`](fill_file_snippet_dialog.dart) | Real file editor + insert bar for a `fill_file` snippet (text and objects) |
| [`schedule_format.dart`](schedule_format.dart) | DSL parse / format (`daily` / `weekly` / `weekly DAY,DAY` / `monthly` / `monthly N … from YYYY-MM`) |
| [`schedule_kind_field.dart`](schedule_kind_field.dart) | Once a day / week / month, a few times a week or month, every N months chips |
| [`automation_service.dart`](automation_service.dart) | Automations API |
| [`automation.dart`](automation.dart) | Model, scope kinds, step kinds |

## Rules

- Never build a schedule string by hand; use the structured controls.
- Scope is required.
- A disabled automation must not appear as active. The on/off switch lives on the list and PATCHes `enabled` only.
- Refresh the current topic after a run completes — otherwise the user sees stale content.
- Do not put automations on the AI bar. That bar is for actions you press while looking at something.
