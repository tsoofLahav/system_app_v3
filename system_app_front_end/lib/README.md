# `lib/` overview

```
lib/
├── main.dart, app.dart    bootstrap and provider wiring
├── areas/                 the six system areas — see areas/README.md
├── core/                  app-wide state, API client, l10n, platform
├── shared/utils/          clipboard, image picking, platform text
└── config/                API base URL
```

**Start with [`areas/README.md`](areas/README.md).** Each area has an `AREA.md` that owns its rules.

## What stays outside the areas

| Path | Why |
|------|-----|
| `core/app_state.dart` | Single app-wide state object; delegates to area services |
| `core/services/api_service.dart` | HTTP client used by every area |
| `core/services/bootstrap_service.dart`, `image_service.dart`, `tag_service.dart` | Cross-area services |
| `core/l10n/` | English/Hebrew strings and RTL rules — see [`BILINGUAL.md`](core/l10n/BILINGUAL.md) |
| `core/platform/` | Desktop vs phone form factor |
| `shared/utils/` | Platform helpers with no domain knowledge |

## Dependency direction

```
areas/*  →  core, shared, areas/ui
core     →  models and services only, never area widgets
areas/ui →  nothing app-specific (presentational only)
```

## Placement rules

- Domain workflow that spans areas → `core/app_state.dart`
- Area-specific API calls → that area's `data/` folder
- Anything visual (color, font, radius, glass) → `areas/ui/`
- Anything about where things appear or how the user moves around → `areas/ux/`

## Legacy

`core/models/block.dart` and `core/models/part.dart` are v1 shapes that no live code depends on. Do not build on them.
