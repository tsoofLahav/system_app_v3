# `features/tasks/`

Purpose: shared task list UI for topic task files and view panes.

## Architecture

Tasks are shown in **two zones** (active on top, done below with a divider when done tasks exist). Each zone is independent — no shared multiline document, no line-diff sync.

| File | Role |
|---|---|
| `task_lines_editor.dart` | Composes active + done `TaskZoneList` columns |
| `task_zone_list.dart` | One zone: `TaskRow` per task + draft row for new tasks |

Topic files wire through [`tasks_connected_editor.dart`](../blocks/tasks_connected_editor.dart). View panes wire through [`view_pane_tasks_editor.dart`](../task_view/view_pane_tasks_editor.dart).

## Behavior

- **Order:** tasks sorted by `task.id` (creation order). Mark/unmark does not reorder blocks.
- **Toggle:** `PATCH status` only; UI moves the row between zones via `partitionTasksById`.
- **Per-row actions:** edit title → `PATCH`; Enter after a row → `POST` with same zone status; empty + Backspace → `DELETE`; paste → create tasks after the row.
- **Topic files:** `AppState.createTaskInFileAfter`, `deleteTaskInFile`, `pasteTasksInFileAfter`.
- **View panes:** `createTaskInViewZoneAfter`, `deleteTaskInView`, `pasteTasksInViewAfter`; by-section creates may open the topic picker.

## Shared helpers

[`lib/core/task_list_order.dart`](../../core/task_list_order.dart) — `partitionTasksById`, `sortTasksById`.

Row primitives: [`lib/shared/widgets/task_row.dart`](../../shared/widgets/task_row.dart), [`task_mark.dart`](../../shared/widgets/task_mark.dart).

`ConnectedLinesEditor` remains for **`list`** blocks only, not task lists.
