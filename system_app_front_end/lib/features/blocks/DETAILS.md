# Details blocks

Reusable topic-scoped text stored as `blocks.type = "details"`. Two distinct flows — do not conflate them.

## Storage

```json
{
  "title": "Chicken soup recipe",
  "text": "Ingredients…",
  "spans": []
}
```

- Lives in any file under a topic (often a `doc` / `data` library file)
- No separate `details` table — search scans blocks in the topic

## Flows

| Flow | Trigger | Effect |
|------|---------|--------|
| **Copy / upload** | AI `upload_details`, block menu “Insert at cursor” | Inserts title + body text at focused field (editable copy) |
| **Attach (tasks)** | Task menu “Attach details…” | Sets `tasks.details_block_id`; hover shows preview bubble |

Copy does **not** set `details_block_id`. Attach does **not** change the task title.

## Backend

- `GET /topics/:topic_id/details-blocks` — picker + AI index
- `PATCH /tasks/:id` with `details_block_id` (nullable to detach)
- Migration **017** — `tasks.details_block_id` FK → `blocks.id` ON DELETE SET NULL
- [`services/details_lookup.py`](../../../system_app_back_end/services/details_lookup.py)

## Frontend

| File | Role |
|------|------|
| [`details_block_widget.dart`](details_block_widget.dart) | Title + rich body editor |
| [`details_picker_dialog.dart`](details_picker_dialog.dart) | Task attach picker |
| [`../../shared/widgets/details_hover_bubble.dart`](../../shared/widgets/details_hover_bubble.dart) | Task hover preview |
| [`../../core/app_state.dart`](../../core/app_state.dart) | `runUploadDetails`, `attachTaskDetails`, `detailsBlockForId` |
| [`../../core/app_state_task_file.dart`](../../core/app_state_task_file.dart) | Task file mutations (separate from Details attach) |

## AI tool

`upload_details` — `topic_router` → `details_router` → `{ action: "insert", result: text }` → `BlockTextFocusRegistry.insertAiText`.

## Invariants

- Details search/attach is **topic-scoped** (via file → topic)
- Do not add file-type allowlists for rendering
- Deleting a details block clears task links via FK SET NULL

## Extension

- Link Details to other entities (parts, headers): add nullable FK + hover, same picker pattern
- Dedicated library file type: optional follow-up; use existing `doc` files today
