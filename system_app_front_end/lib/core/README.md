# `core/`

Purpose: application state, domain models, and backend integration contracts.

What lives here:
- `app_state.dart`: workflow orchestration and user-action state transitions.
- `models/`: typed frontend representations of API entities.
- `services/`: network/API access per domain.
- `registry/`: declarative rules consumed by UI/features.
- `l10n/`: localization keys and language direction logic.
- `ai/`: AI context and tool request helpers.

Execution model:
- UI triggers actions on `AppState`.
- `AppState` coordinates registry decisions + service calls.
- Services return model objects; `AppState` publishes state updates.

Boundaries:
- Keep UI widget details out of `core/`.
- Keep behavior deterministic and easy to trace from action -> state -> API call.
- Keep business rules in registry/state, not duplicated in widgets.
