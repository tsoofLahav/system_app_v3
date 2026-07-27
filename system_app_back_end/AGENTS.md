# system_app — Backend Guide

Read [`../DEVELOPMENT.md`](../DEVELOPMENT.md) first for v3 status, the deploy loop, and the area map.

**Deploy for testing:** after any backend change, commit and **push to `main`** so Render redeploys.

## Code is organized by area

| Area | Doc |
|------|-----|
| File structure & functionality | [`areas/files/AREA.md`](areas/files/AREA.md) |
| Production agent | [`areas/production_agent/AREA.md`](areas/production_agent/AREA.md) |
| Automations | [`areas/automations/AREA.md`](areas/automations/AREA.md) |
| Objects (incl. tasks) | [`areas/objects/AREA.md`](areas/objects/AREA.md) |

Area map and rules: [`areas/README.md`](areas/README.md)

Read the relevant `AREA.md` before changing that area, and update it in the same commit.

## Layout

```
system_app_back_end/
├── app.py              Flask app factory + /health
├── config.py           DATABASE_URL, UPLOAD_FOLDER, AI config
├── models.py           All SQLAlchemy models + to_dict()
├── areas/              Areas — each with routes/, services/, AREA.md
├── shared/             helpers, bootstrap, workspace/tag/upload/bootstrap routes
├── scripts/            Cron entry point, agent prompt sync
├── migrations/         Manual SQL
└── tests/              Grouped by area
```

## Tech stack

| Layer | Choice |
|-------|--------|
| Framework | Flask 3 |
| ORM | Flask-SQLAlchemy / SQLAlchemy 2 |
| Database | PostgreSQL on Render |
| Production server | gunicorn (`Procfile`) |
| Image storage | Local disk (`/var/data/uploads` on Render) |

No authentication — do not add it unless asked.

## Conventions

**Adding an endpoint**

1. Extend `models.py` with a `to_dict()`.
2. Add or extend a blueprint in the owning area's `routes/`.
3. Register it in [`areas/__init__.py`](areas/__init__.py).
4. Use [`shared/helpers.py`](shared/helpers.py): `get_or_404`, `apply_updates`, `parse_datetime`.

**Serialization** — every model returns JSON-safe primitives via `to_dict()`. Never return SQLAlchemy objects.

**PATCH** — partial updates only. Omitted fields are unchanged; send `null` to clear.

**Errors** — registered in `shared/helpers.py`: `HTTPException` keeps its status, `ValueError` → 400, anything else → 500 with rollback. Never expose stack traces.

**Naming** — the `File` model shadows nothing in Python but is easy to confuse; always `from models import File`.

## What to avoid

- Do not modify [`../CONSTITUTION.md`](../CONSTITUTION.md).
- Do not add authentication unless asked.
- Do not call `db.create_all()` — schema is applied via `migrations/`.
- Do not duplicate task state anywhere; views reference tasks.
- Do not store uploaded image bytes in PostgreSQL.
- Do not commit secrets; `DATABASE_URL` comes from the environment.

## Verification

```bash
python -m pytest            # from system_app_back_end/
curl http://localhost:5001/health
```

Endpoint reference: [`docs/API.md`](docs/API.md)
