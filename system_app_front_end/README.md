# system_app_front_end

Frontend (Flutter desktop) for `system_app`.

## Before Working

- Read [`AGENTS.md`](AGENTS.md) first.
- For product direction, read [`../CONSTITUTION.md`](../CONSTITUTION.md) before planning large changes.

## Agent Start Path

1. Read [`AGENTS.md`](AGENTS.md) for workflow and guardrails.
2. Read [`lib/README.md`](lib/README.md) for architecture and placement rules.
3. Read the local folder `README.md` before editing code in that folder.

## Documentation Index

- Architecture overview: [`lib/README.md`](lib/README.md)
- Core layer: [`lib/core/README.md`](lib/core/README.md)
- Feature layer: [`lib/features/README.md`](lib/features/README.md)
- Shared widgets: [`lib/shared/README.md`](lib/shared/README.md)
- Design system: [`lib/design_system/README.md`](lib/design_system/README.md)
- Rebuild runbooks: [`docs/runbooks/README.md`](docs/runbooks/README.md)

Use folder-local `README.md` files as the primary source for behavior and structure.

## Run

```bash
flutter pub get
flutter run -d macos
```
