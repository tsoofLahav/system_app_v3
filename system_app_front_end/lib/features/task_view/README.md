# `features/task_view/`

Purpose: view-centric task boards (daily/weekly/monthly/quarterly/arrangements/missions).

What this module covers:
- Rendering task views in two display modes: by section and by topic.
- Section management UI (create, reorder, delete sections).
- Horizontal pane composition for grouped tasks.

Inputs and dependencies:
- `selectedViewType`, `viewTasks`, `viewSections`, and display mode from `AppState`.
- Task membership and section APIs exposed via state workflows.

Main flows:
1. User selects a view from sidebar.
2. `AppState.selectView(...)` loads tasks + sections for that `view_type`.
3. Pane renders by-section or by-topic grouping.
4. Section and task actions dispatch back through `AppState`.

Side effects and persistence:
- Section create/reorder/delete persists through task-view endpoints.
- Section importance (`section_flag` on `task_views`, value `important`) propagates to all tasks in that section for filtering/automation.
- Task status updates persist through task endpoints and reflect across views.

Data contract assumptions:
- Tasks are loaded by `view_type`.
- Section placeholders are loaded and ordered separately.

Extension rules:
- New view types should be added in registry + localization + backend support.
- Keep grouping/presentation logic in this module; keep row primitives shared.

Keep shared row-level widgets in `lib/shared/widgets`.

Runbook:
- [`docs/runbooks/rebuild-task-view-mode.md`](../../../docs/runbooks/rebuild-task-view-mode.md)
