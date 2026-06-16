# `shared/widgets/`

Purpose: composable reusable widgets used across feature modules.

Typical contents:
- Generic rows/cards/chips used by more than one feature.
- Reorder helpers and wrappers used across topic/task flows.
- Small interaction primitives (icons, disclosure helpers, wrappers).

Standards:
- Keep inputs explicit and minimal.
- Avoid direct dependencies on one feature's private state shape.
- If usage narrows to one feature, move it back to that feature folder.
