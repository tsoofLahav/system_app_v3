# `features/shell/`

Purpose: application frame and global controls.

What this module owns:
- Shell layout composition (sidebar + content + bottom bar).
- Global commands and app-level mode toggles.
- The main automation menu for user-visible automations, including enable/disable and schedule editing.
- Visual framing that is shared across topic and task-view modes.

| File | Role |
|---|---|
| `app_shell.dart` | Shell layout: sidebar + content pane + bottom bar |
| `app_bottom_bar.dart` | Bottom bar controls and mode indicators |
| `automation_dialog.dart` | Automation menu and schedule editing |
| `automation_abandon_dialog.dart` | Confirm abandoning in-progress automation |
| `preferences_dialog.dart` | App preferences |
| `process_documentation_input_dialog.dart` | Process documentation input flow |
| `process_update_batch_dialog.dart` | Batch process update review |

Inputs and dependencies:
- `AppState` mode flags (`isViewMode`, `paneDragMode`, selected context).
- Feature panes from `topic/` and `task_view/`.

Main flow:
1. Read global mode from `AppState`.
2. Render sidebar + active pane + bottom controls. Topic ↔ task view switches use `AnimatedSwitcher` with `viewPaneReady` so cached view panes cross-fade without flashing loaders on topic→topic navigation.
3. Dispatch global actions (home, toggles, preferences, automation settings) back to `AppState`.

Side effects and persistence:
- Shell itself should not persist data.
- Persistent effects happen through `AppState` actions and services.

Extension rules:
- Add global controls here only if they affect multiple features.
- Show only main user-facing automations in the automation menu; primitive helper actions stay internal.
- Keep the automation menu as an overview: current timing, enable/disable, edit time, and run now.
- Edit automation timing in a separate dialog with structured controls: frequency, calendar day when needed, month placement when needed, and 24-hour time.
- Feature-specific controls belong in the feature module, not shell.

Guidelines:
- Keep shell orchestration-focused and lightweight.
- Delegate domain actions to `AppState` and feature modules.
