# `lib/` Overview

This folder contains all frontend application code.

Structure:
- `main.dart`, `app.dart`: app bootstrap, provider wiring, app shell entry.
- `config/`: runtime config such as API base URL.
- `core/`: state orchestration, models, registries, services.
- `features/`: user-facing screens and feature modules.
- `shared/`: reusable cross-feature widgets/utilities.
- `design_system/`: tokens and reusable visual primitives.

Dependency direction:
- `features/` -> `core/`, `shared/`, `design_system/`
- `shared/` -> `core/`, `design_system/` (when needed)
- `core/` -> models/services/registry/l10n/ai only (no feature widgets)
- `design_system/` should stay feature-agnostic

Placement rules:
- Put domain workflows in `core/app_state.dart`.
- Put network/API calls in `core/services/`.
- Put cross-feature widgets in `shared/widgets/`.
- Put feature-specific UI in `features/<feature>/`.
