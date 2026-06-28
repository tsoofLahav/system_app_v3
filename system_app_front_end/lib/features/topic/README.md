# `features/topic/`

Purpose: topic canvas and file-pane experience.

What this module covers:
- Topic page composition (`TopicView`) and file-pane layout rendering.
- Main vs additional file grouping rules in presentation (including the main topic).
- Reorder-mode UI behavior and drag/drop interactions; main section holds up to 3 files.

Inputs and dependencies:
- Topic detail state (`selectedDetail`, files, blocks, tasks) from `AppState`.
- Layout selection state and reorder mode flag.
- Reorder helpers from `shared/widgets`.

Main flows:
1. Load topic detail through `AppState.selectTopic`.
2. Render files in layout mode (normal editing flow); primary `FileLayoutBoard` uses viewport-based `slotHeight`.
3. Render split-frame reorder mode when pane-drag mode is enabled.
4. Persist reordered files via `reorderTopicFiles(...)`.

Side effects and persistence:
- Reorder updates persist `order_index` and `is_main`.
- File/block edits delegate to `AppState` and service layer.

Extension rules:
- Add new layout behavior through layout definitions + topic rendering hooks.
- Keep reorder algorithm logic in dedicated helpers, not inline in UI trees.

Move out when reusable:
- Generic reorder helpers/widgets to `shared/widgets`.

Runbook:
- [`docs/runbooks/rebuild-topic-view.md`](../../../docs/runbooks/rebuild-topic-view.md)
- [`docs/runbooks/rebuild-reorder-mode.md`](../../../docs/runbooks/rebuild-reorder-mode.md)
