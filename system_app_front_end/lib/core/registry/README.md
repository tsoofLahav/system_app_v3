# `core/registry/`

Purpose: declarative product rules and defaults (the decision layer).

What lives here:
- File catalog per topic type (`file_registry.dart`).
- File behavior profiles (`file_behavior_registry.dart`): default blocks, right-click suggestions, and inline insert behavior.
- Block type catalog (`block_registry.dart`): known block types only, not per-file restrictions.
- Topic appearance defaults (icon/color choices).
- View definitions and display metadata.

Decision precedence:
1. Explicit backend state (`is_main`, `order_index`, stored settings).
2. Registry defaults/fallbacks.
3. UI-level display choices.

Examples:
- Which files are main by default for a topic type.
- Which blocks a file starts with.
- Which block types are suggested in a file context menu.
- Which views appear in the sidebar and their labels.

## File Behavior Model

File type controls creation UX, not capability. Any file may contain any block type; file type only decides which blocks appear by default, which blocks are suggested on right-click, and what a gap click inserts.

The file name is the visible editable header. Profiles do not seed an extra `header` block by default, but most files can add inner `header` blocks from the right-click menu.

## File Types

| File type and name | Purpose | Recommended template blocks | Default block at end | Right-click suggestions |
|---|---|---|---|---|
| `text` | Free writing and notes | `text` | `text` | `header`, `text`, `summary`, `list`, `image` |
| `overview` | Overview/recap file | `summary`, `task_list`, `table` | `text` | `header`, `text`, `summary`, `task_list`, `table`, `list` |
| `plan` | Planning and steps | `text`, `list` | `text` | `header`, `text`, `summary`, `list`, `image` |
| `tasks` | Dedicated task entry | `task_list` | none | `header`, `task_list` |
| `doc` | Documentation | `table` | `text` | `header`, `text`, `summary`, `graph` |

Task-file editing happens entirely in the `task_list` block (connected lines). No trailing input row.

Topic defaults:
- Projects: `overview`, `text`, `tasks`
- Processes: `overview`, `plan`, `tasks`, `doc`
- Areas: `tasks`, `doc`
- When adding a file to a topic, every file type is available regardless of topic type.

How to use it:
- Add/adjust rules here first, then adapt UI behavior in features.
- Keep these files data-first (simple constants/maps), not widget logic.
- Avoid hardcoding the same rule in multiple places.
