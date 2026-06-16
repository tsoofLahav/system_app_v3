# `features/shell/`

Purpose: application frame and global controls.

What this module owns:
- Shell layout composition (sidebar + content + bottom bar).
- Global commands and app-level mode toggles.
- Visual framing that is shared across topic and task-view modes.

Inputs and dependencies:
- `AppState` mode flags (`isViewMode`, `paneDragMode`, selected context).
- Feature panes from `topic/` and `task_view/`.

Main flow:
1. Read global mode from `AppState`.
2. Render sidebar + active pane + bottom controls.
3. Dispatch global actions (home, toggles, preferences) back to `AppState`.

Side effects and persistence:
- Shell itself should not persist data.
- Persistent effects happen through `AppState` actions and services.

Extension rules:
- Add global controls here only if they affect multiple features.
- Feature-specific controls belong in the feature module, not shell.

Guidelines:
- Keep shell orchestration-focused and lightweight.
- Delegate domain actions to `AppState` and feature modules.
