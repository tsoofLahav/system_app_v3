# Project Parts

Parts are topic-scoped entities for **project** topics. A part exists in the topic's memory before it appears in every file.

## Model

| Layer | Owner |
|-------|-------|
| Identity | `parts` table — `id`, `topic_id`, `name`, `order_index` |
| Placement | `header` block in a file + following blocks with `blocks.part_id` |
| Preamble | Blocks with `part_id = null` before the first part header |

Header content shape:

```json
{ "text": "Part name", "level": 2, "part_id": 12 }
```

`parts.name` is canonical. Header `text` mirrors it for rich-text editing.

## Supported files

Part placement is enabled for `plan`, `execution`, and `tasks` files only.

Default blocks inserted after the header:

| File type | Blocks |
|-----------|--------|
| `plan` | empty `list` |
| `execution` | empty `text` + empty `list` |
| `tasks` | one empty `task` row |

When the file still has only factory placeholder blocks, the first part placement replaces them instead of appending below.

## UI flows

Right-click in a supported file → **Add part**:

- **New part…** — creates `parts` row + header + defaults in the current file only
- **Existing part…** — picker of parts not yet placed in this file; inserts header + defaults

Registry: `FileBehaviorRegistry.supportsPartPlacement(fileType)`.

State: `AppState.addNewPartToFile`, `addExistingPartToFile`, `partsAvailableForFile`.

API: `POST /files/<file_id>/parts`.

## Headers

All inner `header` blocks render **bold** with **top spacing** when content appears above them (`HeaderBlockWidget.hasContentAbove`).

Generated overview headers use the same style — no `is_current_part` highlight.

## Automation

`project_summary_update` reads parts from the `parts` table via `part_resolver.py`. Flagged tasks split by `task.block.part_id`. Overview output does not emit `is_current_part`.

## Related

- Backend: [`../../../system_app_back_end/docs/automation.md`](../../../system_app_back_end/docs/automation.md)
- Registry: [`../../core/registry/README.md`](../../core/registry/README.md)
