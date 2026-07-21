# `features/tasks/`

Purpose: shared task list UI for topic **tasks files** and view panes.

**Canonical spec for topic task files:** [`TASK_FILES.md`](TASK_FILES.md) — ordering, drag, flip mode, create/delete, invariants.

## Key files

| File | Role |
|------|------|
| [`TASK_FILES.md`](TASK_FILES.md) | Agent reference — data model, flows, drag matrix, pitfalls |
| `task_lines_editor.dart` | Composes active + done `TaskZoneList` columns |
| `task_zone_list.dart` | One zone: `TaskRow` per task, drag/drop, draft row |
| `tasks_flip_editor.dart` | Flip-by-view grouping (`tasks_flip_by_view` setting) |
| `task_drag_data.dart` | Pure drop classification (`resolveTaskDrop`) |

Topic files wire through [`tasks_connected_editor.dart`](../blocks/tasks_connected_editor.dart). View panes wire through [`view_pane_tasks_editor.dart`](../task_view/view_pane_tasks_editor.dart) — same row widgets, different `AppState` entry points (`createTaskInViewZoneAfter`, etc.).

## Behavior (summary)

- **Order:** active zone then done; within each zone by `list_order_index` (regular / unassigned flip) or `task_views.order_index` (assigned flip). Not `task.id`.
- **Toggle:** `PATCH status` only; UI moves row between zones via `partitionTasksById`.
- **Drag:** `applyTaskDrop` writes order via task/view APIs — never reorders file row blocks.
- **Topic files:** `createTaskInFileAfter`, `deleteTaskInFile`, `pasteTasksInFileAfter` in [`app_state_task_file.dart`](../../core/app_state_task_file.dart).

## Shared helpers

[`lib/core/task_file_layout.dart`](../../core/task_file_layout.dart) — list regions, display sort, flip grouping.

[`lib/core/task_list_order.dart`](../../core/task_list_order.dart) — `partitionTasksById`, `sortTasksById`.

Row primitives: [`lib/shared/widgets/task_row.dart`](../../shared/widgets/task_row.dart), [`task_mark.dart`](../../shared/widgets/task_mark.dart).

`ConnectedLinesEditor` remains for **`list`** blocks only, not task lists.
