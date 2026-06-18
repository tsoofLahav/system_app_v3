# Rebuild Reorder Mode

## Scope
Rebuild pane reorder interaction for topic files with main/additional sections and persistence.

## Required Layers
- `lib/features/topic/`
- `lib/shared/widgets/pane_reorder_*`
- `lib/core/app_state.dart` (`paneDragMode`, `reorderTopicFiles`)
- `lib/features/shell/` (global toggle placement)

## Steps
1. Expose a global reorder mode toggle in shell controls.
2. In topic view, branch between normal layout and reorder canvas when toggle is on.
3. Render two reorder frames: main (4-row viewport) and additional (scrollable).
4. Support drag/drop within and across lists, including full-main push behavior.
5. Hide dragged item from original slot during drag for true pickup feel.
6. Persist final ordering via `reorderTopicFiles` (`order_index` + `is_main`).

## Validation
- Reordering works within main, within additional, and across sections.
- Full-main insertion moves the last main file to additional top.
- Reorder mode remains active while switching topics.
- Refresh preserves final order and section assignment.
