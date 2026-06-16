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
| `tasks` | Dedicated task entry | `task_list` | none | `header`, `task_list` |
| `doc` | Documentation | `table`, `text` | `text` | `header`, `text`, `summary`, `graph` |

The file name is the visible editable header. Profiles do not seed an extra `header` block by default.

Topic defaults:
- Projects: `overview`, `text`, `tasks`
- Processes: `overview`, `plan`, `tasks`, `doc`
- Areas: `tasks`, `doc`

## UI

- File corner `...` = file actions only (delete, main/additional visibility)
- Right-click inside file = profile-filtered block insert menu
- Files with a text default keep an empty text block at the end.
- Right-click menus open at the pointer.
- Lists and task entry continue by pressing Enter, not by visible "add" buttons.
- Table row/column actions live in a right-click menu on the table.
- Right-click inside a table opens only the table menu; right-click outside a table opens the file block menu.
- AI tools may insert any block type anywhere

The corner menu contains file actions only: delete file, show on main, and move to additional files.

## Block Taxonomy

- `header`: optional inner section block; the file name is the primary header.
- `text`: free writing.
- `summary`: standalone summary text, manually written or AI-filled.
- `task_list`: task entry anchor for task files and recap files.
- `task`: canonical task reference block.
- `image`: uploaded or generated visual block.
- `table`: editable grid block for documentation and recap structures.
- `graph`: placeholder/rendering target for AI graph insertion.
- `list`: structured points or numbered list block.
- `measurement`: specialized measured value block.

Recap is a file composition, not a `recap` block type. Recap files are built from the editable file title plus `table`, `task_list`, and `list`.

## Validation

- AI summarize, image, and graph actions can insert into any file.
- No renderer shows an unsupported-block message solely because of file type.
- The corner `...` menu shows only file actions.
- Right-click options differ by behavior profile.
- Empty trailing text blocks are reused instead of creating duplicate empty text blocks.
- New files show the editable file title as their header.

## Source of truth

[`lib/core/registry/file_behavior_registry.dart`](../../lib/core/registry/file_behavior_registry.dart)
