# `features/`

Purpose: user-facing screens and feature modules.

Current modules:
- `shell/`: app frame and global controls.
- `sidebar/`: topic/view navigation.
- `topic/`: topic canvas and file panes.
- `archive/`: read-only archive browse mode (grouped sidebar, file grid, spotlight preview, paginated loading, hybrid search).
- `task_view/`: view-centric task boards.
- `blocks/`: block editors and block interactions.
- `create_topic/`: create/edit topic dialogs.

Guidelines:
- Features compose `core/`, `shared/`, and `design_system/`.
- Move cross-feature UI into `lib/shared/`.

Runbooks:
- Topic and reorder rebuild: [`../docs/runbooks/rebuild-topic-view.md`](../../docs/runbooks/rebuild-topic-view.md), [`../docs/runbooks/rebuild-reorder-mode.md`](../../docs/runbooks/rebuild-reorder-mode.md)
- Task view rebuild: [`../docs/runbooks/rebuild-task-view-mode.md`](../../docs/runbooks/rebuild-task-view-mode.md)
