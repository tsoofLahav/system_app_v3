# Backend areas

Each area owns its routes, services, and an `AREA.md` describing its rules and logic.

| Area | Folder | Doc |
|------|--------|-----|
| File structure & functionality | [`files/`](files/) | [`files/AREA.md`](files/AREA.md) |
| Production agent | [`production_agent/`](production_agent/) | [`production_agent/AREA.md`](production_agent/AREA.md) |
| Automations | [`automations/`](automations/) | [`automations/AREA.md`](automations/AREA.md) |
| Objects (incl. tasks) | [`objects/`](objects/) | [`objects/AREA.md`](objects/AREA.md) |

**UI** and **UX** are frontend-only areas — see [`system_app_front_end/lib/areas/`](../../system_app_front_end/lib/areas/).

## Layout

```
areas/<area>/
├── AREA.md      rules and logic for this area
├── routes/      Flask blueprints
└── services/    business logic
```

`__init__.py` at `areas/` registers every blueprint.

## Outside the areas

| Path | Why it is shared |
|------|------------------|
| `models.py` | One SQLAlchemy schema for all areas |
| `config.py`, `app.py` | App factory and config |
| `shared/helpers.py` | `get_or_404`, `apply_updates`, error handlers |
| `shared/bootstrap.py` | Default workspace creation |
| `shared/routes/` | Workspaces, tags, upload, bootstrap endpoints |

## Rules

- An area may import `models`, `shared`, and **other areas' services** — but not another area's routes.
- Cross-area logic belongs in the area that owns the data, not in the caller.
- Change behavior → update that area's `AREA.md` in the same commit.
