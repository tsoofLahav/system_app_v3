# `features/blocks/`

Purpose: render and edit file blocks, one block type at a time.

What this folder owns:
- Block editors and renderers for block `type` values coming from `blocks.type`.
- Block interactions (text editing, task toggles, list edits, image handling).
- Mapping from block type to appropriate widget behavior.

## Connected lines (lists and tasks)

`list` blocks and `task_list` blocks share one editing model: **one multiline field, one logical item per newline**.

| Widget | Role |
|---|---|
| `connected_lines_editor.dart` | Single `TextField`; Enter / Backspace / arrows behave like plain text. Bullet or checkbox gutter aligns to each logical line (soft wrap does not create items). |
| `points_list_block_widget.dart` | Thin wrapper for `list` blocks. Lines ↔ `content.items[].text` via `updateBlockContent`. |
| `tasks_connected_editor.dart` | Unified editor for all tasks in a file. Lines ↔ individual `tasks` rows via `AppState.syncTasksFromLines`. |
| `line_task_sync.dart` | Prefix/suffix line diff used when syncing task document changes to create/update/delete tasks. |
| `list_text_parse.dart` | Document helpers (`linesFromDocument`, `documentFromLines`) and paste splitting for bullet/semicolon lists. |

**Why:** Per-row `TextField`s with custom Enter/Backspace handlers were fragile (focus jumps, crashes). Native multiline editing handles keyboard navigation; structured data is rebuilt from `\n`-split lines on a debounced sync.

### List blocks (`type: list`)

- Content shape: `{ "items": [{ "text": string }], "list_style": "bullet" | "numbered" }`.
- Storage: one block row; each item is an element in `items`.
- Enter on a line inserts `\n` → new item. Long text wraps visually under the bullet/number.

### Task blocks (`task_list` + `task`)

- **UI:** Only `task_list` renders `TasksConnectedEditor`. Individual `task` blocks stay in the DB for order and IDs but render as `SizedBox.shrink()` when a `task_list` exists in the same file.
- **Data:** Each line maps to one `tasks` row (title) plus one `task` block (`content.task_id`). Order follows `task` block `order_index` in the file.
- **Enter:** Creates a new task with an empty title (persisted immediately). Type on that line to set the title.
- **Sync:** `AppState.syncTasksFromLines` diffs the previous snapshot against the new lines and creates, updates, or deletes tasks/blocks. Checkbox toggles and right-click assign still use per-task APIs.
- **Fallback:** If a file has `task` blocks but no `task_list`, each task still renders via `TaskBlockWidget` / `TaskRow` (legacy path).

### Other block types

- `header` — optional inner section; file name is the primary header.
- `text` / `summary` — `{ "text": string }`; single-field editors (`text_block_widget.dart`, etc.).
- `checklist` — per-row fields today (not yet on connected-lines model).
- `image`, `table`, `graph` — see respective widgets.

## Common block types (quick reference)

| type | Content shape (main fields) |
|---|---|
| `text` | `{ "text": string }` |
| `summary` | `{ "text": string }` |
| `list` | `{ "items": [{ "text" }], "list_style" }` |
| `task_list` | anchor block; tasks live in `tasks` table |
| `task` | `{ "task_id": number }` |
| `table` | `{ "rows": [[string]] }` |
| `image` | `{ "image_path", "filename" }` |
| `graph` | chart metadata for `graph_block_widget.dart` |

Inputs and dependencies:
- Block payloads and related tasks from `AppState` topic detail.
- Behavior-profile suggestions from `core/registry`.
- Shared primitives from `shared/widgets` and `design_system`.

Main flow:
1. Read block `type` and `content`.
2. Render editor/view widget for that type.
3. Send updates through `AppState` (often optimistic) to persist via services.

Side effects and persistence:
- List content: block `PATCH` via `scheduleBlockSave`.
- Task lines: task `POST` / `PATCH` / `DELETE` plus matching `task` block create/delete via `syncTasksFromLines`.

Extension rules:
- For a new block type: define intent and data shape, add renderer/editor, and wire persistence path.
- Keep type dispatch explicit in `block_renderer.dart`.
- Do not add file-type allowlist checks here. File type can suggest blocks, but rendering must accept any known block type in any file.
- For line-based blocks, extend `ConnectedLinesEditor` (gutter/accessory columns) instead of adding per-row keyboard hacks.
- Avoid visible "add row/item/point" controls. Lists and tasks grow from Enter; table structure actions live in the table right-click menu.

Recap files:
- Recap is a file composition, not a dedicated `recap` block type.
- `overview` files compose the editable file title with `table`, `task_list`, and `list` blocks.
- Recap blocks use the same widgets as every other file.

Boundaries:
- Persistence lives in `AppState` + `core/services`; this folder owns UI behavior.
- Keep cross-feature widgets in `lib/shared/widgets`.
