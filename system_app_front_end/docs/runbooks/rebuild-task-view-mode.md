# Rebuild Task View Mode

## Scope
Rebuild view-based task boards (daily/weekly/monthly/quarterly/arrangements/missions) with section and topic grouping.

## Required Layers
- `lib/features/task_view/`
- `lib/features/sidebar/` (view selection entry)
- `lib/core/app_state.dart` (`selectView`, section/task actions)
- `lib/core/services/task_service.dart`
- `lib/core/services/task_view_service.dart`

## Steps
1. Add/select view definitions through registry and sidebar.
2. Implement `selectView(viewType)` workflow to load tasks and sections.
3. Render task view pane with two display modes: by section and by topic.
4. Add section operations (create/reorder/delete) and wire to state actions.
5. Wire task actions (status toggle, membership/section assignment).
6. Keep row/task primitives reusable via `shared/widgets`.

## Validation
- Selecting any view loads its tasks and sections.
- Section changes persist and reload in correct order.
- Section importance flag (`section_flag = important`) persists on the section placeholder and propagates to all task rows in that section.
- `GET /tasks/view/<view_type>?important=true` returns only tasks in important sections (for automations).
- Task status updates reflect across all relevant views.
- By-section and by-topic display modes show consistent task totals.
