# Area: Production agent (frontend)

Backend twin: [`system_app_back_end/areas/production_agent/AREA.md`](../../../../system_app_back_end/areas/production_agent/AREA.md) — read it for what the agent receives and how it edits files.

This is the **user-facing side** of the AI: how a run is started, and how its result is reviewed.

## AI actions menu

Lives in the bottom bar ([`ai_tool_bar.dart`](ai_tool_bar.dart)) and has two controls:

| Control | Behavior |
|---------|----------|
| **Bolt menu** | Saved AI actions — automations the user marked as manual. Picking one runs it immediately. |
| **Consult button** | Opens a prompt dialog for a one-off request, with **Review changes (diff)** vs **Apply directly** (default review). |

Both are disabled when there is no AI context (nothing selected) or a run is already in flight. `AppState.hasAiContext` and `aiRunning` gate them; `aiRunning` also drives the busy state so the user cannot double-fire.

## Scope and hints come from what is open

The frontend sends preferred context (not a hard tool allow-list — tools may browse the workspace):

```
selected topic  → scope.topic_ids
selected topic's files → scope.file_ids
active editor file → hints.focused_file_id   (tiny pointer; not the file body)
caret line / mark → hints.selected_text      (tiny; selection or caret line only)
```

Before the run, the active editor is flushed so `open_file` matches the open document.
After finish pending / direct apply, the topic reloads; open Super Editors pick up a changed `document_json` and remount from stored text.

## Apply mode

- **Consult** always sends `apply_mode`: `review` | `direct_apply` (dialog default = review).
- If somehow omitted, backend [`DEFAULT_MANUAL_APPLY_MODE`](../../../../system_app_back_end/shared/run_config.py) applies.
- Automations use their stored mode; create UI default is [`agent_run_defaults.dart`](agent_run_defaults.dart).

## Presenting a run result

[`agent_result_ui.dart`](agent_result_ui.dart) branches on the **result**, not a copied mode string:

- `has_pending_review` or any `proposed_changes[].review` → snackbar “Open the file to review changes” (no blocking apply dialog)
- else → snackbar summary; reload topic when `applied`

Pending reviews open when the **file** mounts ([`document_pane.dart`](../files/editor/document_pane.dart) → [`lookalike_review_dialog.dart`](lookalike_review_dialog.dart)):

- Per-hunk Accept | Reject; Finish disabled until all decided
- Finish → `POST /files/:id/pending-review/finish` (archive copy + merge apply)
- Discard → `DELETE /files/:id/pending-review`

| File | Role |
|------|------|
| [`ai_tool_bar.dart`](ai_tool_bar.dart) | Actions menu, prompt dialog + apply toggle, run orchestration |
| [`agent_result_ui.dart`](agent_result_ui.dart) | Result → snackbar |
| [`pending_review_service.dart`](pending_review_service.dart) | GET/DELETE/finish pending |
| [`lookalike_review_dialog.dart`](lookalike_review_dialog.dart) | Per-hunk lookalike review |
| [`agent_run_defaults.dart`](agent_run_defaults.dart) | FE twin of automation apply-mode default |
| [`text_diff_dialog.dart`](text_diff_dialog.dart) | Legacy monospace diff (fallback / unused for pending path) |
| [`change_review_dialog.dart`](change_review_dialog.dart) | Glass shell for review dialogs |
| [`agent_service.dart`](agent_service.dart) | `POST /agent/run` |

## Rules

- Never apply a review proposal without Finish (or Discard) on the lookalike dialog.
- Never hardcode a silent consult `apply_mode` — the dialog chooses and sends it.
- Never show raw JSON to the user — agent-text hunks only.
- Refresh the open topic after Finish so the editor and Archive list update.
- Pass `hints.selected_text` from the active mark so “delete this line” can resolve correctly.

## Not done yet

- Compact undo for `direct_apply`
- Per-hunk review of `create_object` (stays direct_apply)
- Multi-file single combined dialog (each file opens its own pending)
