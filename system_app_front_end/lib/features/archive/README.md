# `features/archive/`

Purpose: read-only browse mode for archived topics and files.

What this module owns:
- Archive topic canvas with grouped sidebar navigation.
- Paginated file grid with hybrid search.
- Spotlight-style file preview pane.

| File | Role |
|---|---|
| `archive_topic_view.dart` | Main archive canvas: search, scroll pagination, delete mode, preview layout |
| `archive_file_grid.dart` | Grid of archived files for the selected topic |
| `archive_file_preview.dart` | Read-only preview of the selected archived file |

Inputs and dependencies:
- `AppState` archive state: `selectedArchiveTopic`, archived file lists, search query, delete mode.
- Topic appearance and file layout helpers from `design_system/` and `core/registry/`.

Main flows:
1. User opens archive from sidebar; `AppState` loads archived topics.
2. User selects a topic; paginated files load with scroll-to-load-more.
3. User searches — hybrid filter across topic and file names.
4. User selects a file; preview pane shows read-only content.
5. Delete mode marks files for permanent removal via `AppState` workflows.

Side effects and persistence:
- Archive loads and deletes go through `AppState` and archive-related services.
- This module is read-only for content editing; no block/task mutations here.

Extension rules:
- Keep archive presentation separate from live topic editing (`features/topic/`).
- New archive interactions should delegate persistence to `AppState`.
- Pagination and search logic belong in state/services, not inline in widgets.

Boundaries:
- Live topic canvas: [`../topic/README.md`](../topic/README.md)
- Block rendering for preview may reuse block widgets in read-only mode.
