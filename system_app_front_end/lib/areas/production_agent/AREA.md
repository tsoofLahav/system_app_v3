# Area: Production agent (frontend)

Backend twin: [`system_app_back_end/areas/production_agent/AREA.md`](../../../../system_app_back_end/areas/production_agent/AREA.md) — read it for what the agent receives and how it edits files.

This is the **user-facing side** of the AI: how a run is started, and how its result is reviewed.

## The AI bar

Lives in the bottom bar ([`ai_tool_bar.dart`](ai_tool_bar.dart)), left to right:

| Control | Behavior |
|---------|----------|
| **Pinned actions** | Up to six saved actions in slot order, each with its icon and its own key (⌘⇧2…⌘⇧7). Pressing one runs it on what is open. |
| **Bolt menu** | Every saved action — the menu only fires things. |
| **⋯** | Opens the automations dialog to rename, re-icon, re-seat, or delete an action. Managing sits beside the menu, not inside it. |
| **Agent button** | Opens the prompt dialog ([`agent_prompt_dialog.dart`](agent_prompt_dialog.dart)) for a one-off request, with **Review changes (diff)** vs **Apply directly** (opens on apply directly — a one-off ask is lighter with the undo toast than with a diff). |

The agent button is last and never moves: it is the one control that is always there, so it must always be in the same place. Everything is disabled when there is no AI context (nothing selected) or a run is already in flight — `AppState.hasAiContext` and `aiRunning` gate them, and `aiRunning` drives the busy state so the user cannot double-fire.

### Keeping an ask

The prompt dialog opens small. **Save as action…** grows it into a name, an icon grid and a seat choice, and the footer becomes Cancel / Save and run / Save — naming and placing something is only interesting once the user has decided to keep it. Saving writes a manual automation ([automations](../automations/AREA.md)); it is the same record the automations dialog creates.

A saved action runs through `runSavedAgentAction` and ends the same way a typed prompt does — review dialog, undo toast, or summary.

## Scope and hints come from what is open

The frontend sends preferred context (not a hard tool allow-list — tools may browse the workspace):

```
selected topic  → scope.topic_ids
selected topic's files → scope.file_ids
active editor file → hints.focused_file_id   (tiny pointer; not the file body)
caret line / mark → hints.selected_text      (tiny; selection or caret line only)
local clock → hints.today / weekday / now    ([`agent_time_hints.dart`](agent_time_hints.dart))
```

The clock hints are not optional: without them the model dates a line from memory. Send the **local** day — the backend can only fall back to UTC, which is the wrong date late in the evening.

Before the run, the active editor is flushed so `open_file` matches the open document.
After finish pending / direct apply, the topic reloads; open Super Editors pick up a changed `document_json` and remount from stored text.

## Apply mode

- **Consult** always sends `apply_mode`: `review` | `direct_apply` (dialog default = review).
- If somehow omitted, backend [`DEFAULT_MANUAL_APPLY_MODE`](../../../../system_app_back_end/shared/run_config.py) applies.
- Automations use their stored mode; create UI default is [`agent_run_defaults.dart`](agent_run_defaults.dart).

## Presenting a run result

[`agent_result_ui.dart`](agent_result_ui.dart) branches on the **result**, not a copied mode string:

- `has_pending_review` / review proposals → if any edited file is **already on screen**, open lookalike dialogs in a queue (Finish/Discard on one → next pending on-screen file); otherwise snackbar “Open the file to review changes”
- `applied` with `undo` cards → compact undo toast queue ([`compact_undo_toast.dart`](compact_undo_toast.dart)): file + topic + change summary, **Undo** / **X** / ~8s auto-close; next file when one closes
- else → snackbar summary; reload topic when `applied`

Pending also opens when the **file** mounts ([`document_pane.dart`](../files/editor/document_pane.dart) → [`pending_review_ui.dart`](pending_review_ui.dart) → [`lookalike_review_dialog.dart`](lookalike_review_dialog.dart)). After a dialog closes, the same helper continues to any other on-screen file that still has pending.

### The review dialog

Two file panes on `AppGlassStyle.dialog` glass, each a `NoteCard` in the topic's tint: **Current** on the left, **Suggested** on the right, both showing the whole file.

- Panes render real blocks — headings, lists, tables, tasks, graphs — never marker text. Agent text is parsed by [`agent_text_blocks.dart`](../files/model/agent_text_blocks.dart) and drawn by [`read_only_document_view.dart`](../files/editor/read_only_document_view.dart).
- A hunk is mapped to the lines it touches ([`review_marks.dart`](review_marks.dart)). One table row, task or list item is one agent-text line, so a change inside an embed tints that row alone; a hunk over the whole fence tints the embed.
- States: pending (faint op tint), active (stronger tint plus a left rule), accepted (teal with a check), rejected (grey, dimmed, with a cross). Word marks stay for changed text lines.
- One bubble in the gutter between the panes carries `n / m` and Accept | Reject. Deciding advances it to the next undecided change and scrolls both panes there. Enter accepts, Backspace rejects, Up/Down walk the changes.
- On the last decision the bubble disappears and Finish lights up, so attention moves to the one thing left to do. Clicking any change brings the bubble back to flip that choice.
- Finish (disabled until all decided) → `POST /files/:id/pending-review/finish` (archive copy + merge apply); Discard → `DELETE /files/:id/pending-review`.

| File | Role |
|------|------|
| [`ai_tool_bar.dart`](ai_tool_bar.dart) | Pinned action buttons, bolt menu, agent button |
| [`agent_prompt_dialog.dart`](agent_prompt_dialog.dart) | Prompt + apply toggle + save-as-action, run orchestration |
| [`agent_result_ui.dart`](agent_result_ui.dart) | Result → dialog or snackbar; runs a saved action |
| [`pending_review_ui.dart`](pending_review_ui.dart) | Shared open-pending helper (anti double-open) |
| [`pending_review_service.dart`](pending_review_service.dart) | GET/DELETE/finish pending |
| [`lookalike_review_dialog.dart`](lookalike_review_dialog.dart) | Two file panes on glass + the moving bubble |
| [`review_marks.dart`](review_marks.dart) | Hunk lines → change state, tint and mark |
| [`compact_undo_toast.dart`](compact_undo_toast.dart) | Direct-apply undo toast queue |
| [`agent_run_defaults.dart`](agent_run_defaults.dart) | FE twin of automation apply-mode default |
| [`text_diff_dialog.dart`](text_diff_dialog.dart) | Legacy monospace diff (unused for pending path) |
| [`change_review_dialog.dart`](change_review_dialog.dart) | Glass shell for review dialogs |
| [`agent_service.dart`](agent_service.dart) | `POST /agent/run` |

## Rules

- Never apply a review proposal without Finish (or Discard) on the lookalike dialog.
- Never hardcode a silent consult `apply_mode` — the dialog chooses and sends it.
- Never show raw JSON to the user — agent-text hunks only.
- Refresh the open topic after Finish so the editor and Archive list update.
- Pass `hints.selected_text` from the active mark so “delete this line” can resolve correctly.

## Not done yet

- Undo for `create_object` alone / long-lived DB undo
- Per-hunk review of `create_object` (stays direct_apply)
- Multi-file single combined lookalike dialog (each file still has its own dialog, queued)
