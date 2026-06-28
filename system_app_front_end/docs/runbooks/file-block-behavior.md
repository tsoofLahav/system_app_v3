# File and Block Behavior

## Product Rule

File type controls creation UX (defaults, menus, inline insert). It does **not** forbid block types globally.

Any file may contain any block type. This keeps manual editing and existing AI tools free to insert useful blocks wherever the user is working.

## File Types

| File type | Purpose | Default blocks | Gap insert | Right-click suggestions |
|---|---|---|---|---|
| `text` | Free writing and notes | `text` | `text` | `image`, `summary`, `header`, `text` |
| `overview` | Overview/recap file | `summary`, `task_list`, `table`, `text` | `text` | `header`, `text`, `summary`, `task_list`, `table`, `list` |
| `plan` | Planning and steps | `text`, `list`, `text` | `text` | `header`, `text`, `summary`, `list`, `image` |
| `tasks` | Dedicated task entry | `task_list` | none (edit in `task_list`) | `header`, `task_list` |
| `doc` | Documentation | `table`, `text` | `text` | `header`, `text`, `summary`, `graph` |
| `board` | Free-form image canvas | `board` | none | none (canvas toolbar) |

The file name is the visible editable header. Profiles do not seed an extra `header` block by default.

Topic defaults:
- Projects: `overview`, `text`, `tasks`
- Processes: `overview`, `plan`, `tasks`, `doc`
- Areas: `tasks`, `doc`

## UI

- File corner `...` = file actions only (delete, main/additional visibility)
- Right-click inside file = glass bubble menu (`AppContextMenu`): **Add block →** hover submenu for profile-filtered inserts, plus block/text actions. See [`lib/shared/widgets/README.md`](../../lib/shared/widgets/README.md).
- Files with a text default keep a text block at the end (never two consecutive text blocks).
- On topic load, adjacent empty text blocks after another text block are removed; trailing ensure skips when the file already ends with text.
- **Board files** use a single `board` block and a canvas UI (not a block list): upload images, drag anywhere, resize freely. No trailing text block and no right-click block menu inside the pane.
- Right-click menus open at the pointer.
- Lists and task entry continue by pressing Enter, not by visible "add" buttons.
- **`list` and `task_list` use one connected multiline editor** (`ConnectedLinesEditor`): each newline is one item/task; soft wrap stays on the same item. See [`lib/features/blocks/README.md`](../../lib/features/blocks/README.md).
- Task files edit all tasks inside the `task_list` block. There is no separate bottom task input. Empty lines are real tasks (empty title) so Enter can open a new row without the cursor jumping back.
- Individual `task` blocks remain in the file for order/IDs but are hidden when a `task_list` is present.
- Table row/column actions live in a right-click menu on the table.
- Right-click inside a table opens only the table menu; right-click outside a table opens the file block menu.
- Right-click inside a text/header/summary block: format (bold, size, etc.) applies to marked text or the current paragraph; selection stays visible via a paint-only overlay. See [RICH_TEXT.md](../../lib/features/blocks/RICH_TEXT.md).
- AI tools may insert any block type anywhere

The corner menu contains file actions only: delete file, show on main, and move to additional files.

## Block Taxonomy

- `header`: optional inner section block; the file name is the primary header.
- `text`: free writing; optional inline `spans` for bold/italic/underline/size.
- `summary`: standalone summary text; same rich-text model as `text`.
- `task_list`: unified task editor anchor; renders all task titles for the file in one connected document.
- `task`: canonical task reference block (order + `task_id`); hidden in UI when `task_list` exists in the same file.
- `image`: uploaded or generated visual block.
- `table`: editable grid block for documentation and recap structures.
- `graph`: bar/line/pie chart with A/B/C default columns, editable name/value grid; right-click to add/remove variables, change colors, or switch chart type.
- `list`: structured points or numbered list block.
- `measurement`: specialized measured value block.

Recap is a file composition, not a `recap` block type. Recap files are built from the editable file title plus `table`, `task_list`, and `list`.

## Validation

- AI summarize, image, and graph actions can insert into any file.
- No renderer shows an unsupported-block message solely because of file type.
- The corner `...` menu shows only file actions.
- Right-click options differ by behavior profile.
- Empty trailing text blocks are reused instead of creating duplicate empty text blocks.
- Files never end with two consecutive text blocks (template defaults and trailing ensure share one block).
- New files show the editable file title as their header.

## Source of truth

[`lib/core/registry/file_behavior_registry.dart`](../../lib/core/registry/file_behavior_registry.dart)
