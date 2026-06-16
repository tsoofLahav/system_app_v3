# system_app_front_end

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Pane Reorder Mode

- Reorder mode shows two lists: `main` (up to 4 panes) and `additional` (unlimited).
- The top list has a fixed viewport of 4 row-heights; it can scroll if drag gaps make content taller.
- The divider is fixed between the two frames, and the additional list always starts below it.
- Drag and drop works within each list and across lists.
- Cross-list rule when `main` is full: dropped pane is inserted at the target index in `main`, and the last `main` pane is pushed to the top of `additional`.
- Dropping from `main` to `additional` always works and preserves order around the drop target.
- During drag, temporary drop slots appear; when active they open only a space (no outlined placeholder card).
- On successful drop, ordering is persisted using backend `order_index` and `is_main` updates.
