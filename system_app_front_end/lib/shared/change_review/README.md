# Change Review

Reusable review UI for structured change sets produced by automations or AI actions.

## Contract

- Input: `ChangeSet` with one or more `documents`.
- Each document has `units` (rendered content) and `changes` (only items that differ).
- Output: map of `change_id -> accepted` when the user finishes review.

## Usage

Any feature can open `showChangeReviewDialog` with a backend-produced `change_set` payload. Automations should not implement their own diff UI.

## Ownership

- Backend diff and unit mapping: `services/unit_mapper.py`, `services/diff_engine.py`
- Frontend models: `lib/core/models/change_set.dart`
- Frontend UI: `lib/shared/change_review/change_review_dialog.dart`
