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
- Which files are main by default for a topic type (and for the main topic via `allFileTypes`).
- Main section capacity: at most `maxMainFilesPerTopic` (3) visible files per topic.
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
| `board` | Image canvas / mood board | `board` (items with x/y/width/height) | none | none |
| `execution` | Execution steps (header + list) | `header`, `list` | `text` | `text`, `header`, `summary`, `list`, `graph`, `image` |

Task-file editing happens entirely in the `task_list` block (connected lines). No trailing input row.
Board files store positioned images in one `board` block. Content shape:

```json
{
  "items": [{ "id", "image_path", "filename", "x", "y", "width", "height", "z_index", "crop_*?" }],
  "canvas_width": 960,
  "canvas_height": 540,
  "background_color": 4294967295
}
```

Omitted `canvas_*` / `background_color` use defaults (960×540, translucent white). Right-click on the canvas handles copy/paste and background — not `BlockContextMenu`.

Topic defaults:
- **Main topic:** `allFileTypes` — Text, Recap, and Plan are main by default; Tasks, Documentation, Board, and Execution are additional. Daily (`main`) is always main.
- Projects: `overview` (Summary), `tasks`, `execution` (main); `doc`, `plan` (additional)
- Processes: `overview`, `plan`, `tasks`, `doc`
- Areas: `tasks`, `doc`
- When adding a file to a topic, every file type is available regardless of topic type.

Main section limit: `FileRegistry.maxMainFilesPerTopic` (3). Reorder and promote-to-main evict the last main file when full.

## Project Parts

Projects are organized into ordered **parts**. A part is represented by an inner
`header` block with the same text in the project `plan`, `execution`, and
`tasks` files. The three files should keep the same parts in the same order.

Project file roles:
- `plan`: macro view of the project. It contains all parts with short
  descriptions and should change rarely.
- `execution`: detailed working memory for each part. It accumulates important
  implementation and decision details as the project moves.
- `tasks`: concrete missions split under the same part headers.
- `overview`: generated status surface for the project. It should summarize the
  current state rather than hold primary source content.
- `doc`: chronological documentation and progress notes that can inform the
  generated overview.

The current main part in progress may be represented as metadata on generated
overview headers/list items, such as `is_current_part: true`, so renderers can
highlight it while keeping the visible text stable.

Future project-structure automation can own synchronization:
- If a part exists in one of `plan`, `execution`, or `tasks`, the part header
  should exist in all three files.
- The order of parts should be consistent across the three files.
- Existing content under a part should be preserved. Automation should recreate
  missing headers rather than silently deleting content.

The project summary automation reads the current part structure and only writes
the generated `overview`: current project state, current part, flagged tasks for
the current part, flagged tasks from other parts, recent progress dates, and the
ordered part list.

How to use it:
- Add/adjust rules here first, then adapt UI behavior in features.
- Keep these files data-first (simple constants/maps), not widget logic.
- Avoid hardcoding the same rule in multiple places.
