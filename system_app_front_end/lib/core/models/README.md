# `core/models/`

Purpose: typed frontend representations of backend entities.

What models include:
- Field definitions aligned to backend payloads.
- `fromJson` / serialization helpers.
- `copyWith` helpers for immutable-like state updates.

Core entities:
- `Topic`, `AppFile`, `Block`, `Task`, `TaskViewMembership`, `ViewSection`.
- Models should reflect API contracts, not widget presentation concerns.

Contract notes:
- Preserve backend keys (`view_type`, `section_name`, `order_index`) in parsing.
- Keep nullable fields explicit to avoid hidden fallbacks.

Guidelines:
- Keep models explicit and schema-focused.
- Avoid embedding app workflows or widget logic.
- When API contracts change, update models first, then calling code.
