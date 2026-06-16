# Rebuild Topic View

## Scope
Rebuild the topic page that renders file panes, supports layout mode, and integrates block/task content.

## Required Layers
- `lib/features/topic/`
- `lib/shared/widgets/` (pane/layout helpers)
- `lib/core/app_state.dart`
- `lib/core/models/` and `lib/core/services/`
- `lib/design_system/`

## Steps
1. Build a `TopicView` entry that reads `selectedDetail` from `AppState`.
2. Split files into main/additional groups using state/registry-driven rules.
3. Render main layout mode using shared file-pane widgets.
4. Wire file-level actions (add/delete/update) back to `AppState`.
5. Ensure block/task content previews come from topic detail maps.
6. Add empty/loading/error states consistent with shell behavior.

## Validation
- Opening a topic shows the correct files, blocks, and task summaries.
- Main vs additional grouping matches persisted `is_main` and ordering.
- File-level actions update UI and persist correctly after refresh.
