# `features/blocks/`

Purpose: render and edit file blocks, one block type at a time.

What this folder owns:
- Block editors and renderers for block `type` values coming from `blocks.type`.
- Block interactions (text editing, task toggles, list edits, image handling).
- Mapping from block type to appropriate widget behavior.

Common block types and intent:
- `header` - optional inner section block; the file name is the primary editable header.
- `text` - free writing and notes; content shape: `{ "text": string }`.
- `summary` - hand-written or AI-filled summary text; content shape: `{ "text": string }`.
- `task` / `task_list` - task execution and tracking.
- `image` - visual reference; content shape: `{ "image_path": string, "filename": string }`.
- `table` - editable grid for docs and recap files; content shape: `{ "rows": [[string]] }`.
- `list` - structured points or numbered list; content shape: `{ "items": [{ "text": string }] }`.
- `graph` - graph/diagram placeholder block; content shape may be empty or graph metadata.

Inputs and dependencies:
- Block payloads and related tasks from `AppState` topic detail.
- Behavior-profile suggestions from `core/registry`.
- Shared primitives from `shared/widgets` and `design_system`.

Main flow:
1. Read block `type` and `content`.
2. Render editor/view widget for that type.
3. Send updates through `AppState` (often optimistic) to persist via services.

Side effects and persistence:
- Block content updates are persisted through block service endpoints.
- Task-related block interactions may update both tasks and block content.

Extension rules:
- For a new block type: define intent and data shape, add renderer/editor, and wire persistence path.
- Keep type dispatch explicit and centralized.
- Do not add file-type allowlist checks here. File type can suggest blocks, but rendering must accept any known block type in any file.
- Avoid visible "add row/item/point" controls inside blocks. Lists and tasks continue from Enter; table structure actions live in the table right-click menu.

Recap files:
- Recap is a file composition, not a dedicated `recap` block type.
- `overview` files render as recap behavior by composing the editable file title with `table`, `task_list`, and `list` blocks.
- Recap blocks are manually editable through the same block widgets as every other file.

Boundaries:
- Persistence lives in `AppState` + `core/services`; this folder owns UI behavior.
- Keep cross-feature widgets in `lib/shared/widgets`.
