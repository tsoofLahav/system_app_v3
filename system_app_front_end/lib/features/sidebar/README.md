# `features/sidebar/`

Purpose: navigation between views and topics.

What this module owns:
- Rendering view entries and grouped topic lists.
- Selection/highlight states for current topic/view.
- Topic row actions (open/edit/delete entry points).
- A resizable sidebar width with clipped/ellipsis labels when space is tight.
- A soft-glass sidebar surface that matches app dialogs and floating controls.

Inputs and dependencies:
- `AppState.topics`, `selectedTopic`, `selectedViewType`, and localized labels.
- View definitions from `core/registry`.

Main flow:
1. Render system views and grouped topics.
2. On click, call `selectView(...)` or `selectTopic(...)`.
3. Keep selected item highlighting in sync with state.

Side effects and persistence:
- Sidebar triggers state transitions only; no direct API calls here.
- Topic mutations are delegated through `AppState` workflows.

Extension rules:
- New navigation groups should map to explicit `AppState` selectors/actions.
- Avoid embedding business filtering logic directly in widget build methods.

Guidelines:
- Keep sidebar logic navigation-centric.
- Resolve data and mutations through `AppState`.
- Do not compress labels horizontally when the sidebar is narrow; clip or ellipsize text instead.
