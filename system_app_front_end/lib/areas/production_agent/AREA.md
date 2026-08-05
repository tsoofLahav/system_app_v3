# Area: Production agent (frontend)

Backend twin: [`system_app_back_end/areas/production_agent/AREA.md`](../../../../system_app_back_end/areas/production_agent/AREA.md) — read it for what the agent receives and how it edits files.

This is the **user-facing side** of the AI: how a run is started, and how its result is reviewed.

## AI actions menu

Lives in the bottom bar ([`ai_tool_bar.dart`](ai_tool_bar.dart)) and has two controls:

| Control | Behavior |
|---------|----------|
| **Bolt menu** | Saved AI actions — automations the user marked as manual. Picking one runs it immediately. |
| **Consult button** | Opens a prompt dialog for a one-off request. |

Both are disabled when there is no AI context (nothing selected) or a run is already in flight. `AppState.hasAiContext` and `aiRunning` gate them; `aiRunning` also drives the busy state so the user cannot double-fire.

## Scope and hints come from what is open

The frontend does not ask the user what the AI may touch. It sends the current selection:

```
selected topic  → scope.topic_ids
selected topic's files → scope.file_ids
active editor file → hints.focused_file_id   (tiny pointer; not the file body)
```

This is why the buttons are dead with nothing open — an unscoped agent run is not allowed.
The backend loads content only via tools; the first turn never includes file bodies.

## Diff review dialog

Manual runs use `apply_mode: 'review'`, so the backend proposes instead of writing.

```
run → result.proposed_changes[0].review.diff_hunks
        ↓
   TextDiffDialog  (added lines green, removed red)
        ↓
 accept → applyAgentReview()  → PATCH document_json
 cancel → dismissAgentReview() → nothing written
```

Key points:

- The diff is over **agent text**, not JSON — the user reads sentences, not braces.
- Nothing is written until the user accepts. The backend rolled its session back already.
- On accept, the frontend writes `new_document_json` from the proposal, then reloads the topic so embeds refresh.
- Only the first proposed change is currently shown, even when a run touches several files.

| File | Role |
|------|------|
| [`ai_tool_bar.dart`](ai_tool_bar.dart) | Actions menu, prompt dialog, run orchestration |
| [`text_diff_dialog.dart`](text_diff_dialog.dart) | Renders `diff_hunks` and returns accept/cancel |
| [`change_review_dialog.dart`](change_review_dialog.dart) | Richer structured review surface |
| [`agent_service.dart`](agent_service.dart) | `POST /agent/run` |
| [`ai_proposal.dart`](ai_proposal.dart), [`change_set.dart`](change_set.dart) | Proposal models |

## Rules

- Never write a file from an agent result without explicit user acceptance in `review` mode.
- Never send a run without scope.
- Never show raw JSON to the user — always the agent-text diff.
- Clear `pendingAgentReview` on both accept and cancel so a stale proposal cannot be applied later.
- Refresh the open topic after applying, or the editor will keep showing the pre-agent document.

## Not done yet

Multi-file proposals are returned by the backend but only the first is presented for review.
