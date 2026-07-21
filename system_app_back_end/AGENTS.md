# system_app — Backend Agent Guide

This document is for AI agents and developers working on the **system_app** backend. Read [`../AGENTS.md`](../AGENTS.md) first for monorepo orientation and task routing.

**Deploy for testing:** after any backend change, commit and **push to `main`** so Render redeploys and the app can test against the live API. See git workflow in [`../AGENTS.md`](../AGENTS.md).

## Constitution (read first)

Before any backend work, read [`../CONSTITUTION.md`](../CONSTITUTION.md). It defines the app's purpose, philosophy, UX principles, and architectural direction. Implementation must align with it.

**Do not modify `CONSTITUTION.md`.** It is read-only for agents. If something seems outdated or conflicting, stop and ask the user — never edit that file yourself.

## Project overview

**system_app** is a personal productivity app. The backend is a REST API built with Flask. Backend files live inside `system_app_back_end/` (`app.py`, `models.py`, `routes/`, `services/`). The Flutter frontend lives in `system_app_front_end/` and consumes this API. There is **no authentication** yet — do not add auth unless explicitly requested.

### Tech stack

| Layer | Choice |
|-------|--------|
| Framework | Flask 3 |
| ORM | Flask-SQLAlchemy / SQLAlchemy 2 |
| Database | PostgreSQL (hosted on Render) |
| CORS | Flask-CORS (enabled for Flutter dev) |
| Production server | gunicorn (`Procfile`) |
| Image storage | Local disk (`/var/data/uploads` on Render) |

### Repository layout

```
system_app_back_end/
├── app.py                 # Flask app factory + health check; entry point
├── config.py              # DATABASE_URL, UPLOAD_FOLDER, AI config
├── models.py              # SQLAlchemy models + to_dict() serializers
├── requirements.txt
├── Procfile               # web: gunicorn app:app
├── routes/                # blueprints
├── services/              # AI and automation services
├── docs/                  # API reference, automation subsystem
└── migrations/            # manual SQL migrations
```

## Subsystem docs

| Topic | Doc |
|-------|-----|
| REST endpoints, config, deployment | [`docs/API.md`](docs/API.md) |
| Task order, move, delete cascade | [`docs/TASKS.md`](docs/TASKS.md) |
| Automation rules, runs, definitions | [`docs/automation.md`](docs/automation.md) |
| Shared AI smart update (process + project) | [`services/ai_smart_update/`](services/ai_smart_update/) |

---

## Domain model

The app organizes work as a hierarchy:

```
Topic (project / process / area / others)
  └── File (overview / plan / doc / data / tasks / protocol …)
        └── Block (text / task / header / image / table / measurement …)
              └── Task (optional; task-type blocks link here)
```

Tasks are assigned to at most one **view** via the `task_views` join table (one row per task).

### Entity relationships

```
topics.parent_id  →  topics.id        (self-referential tree)
files.topic_id    →  topics.id
blocks.file_id    →  files.id
tasks.block_id    →  blocks.id
task_views.task_id → tasks.id
```

### Tables (already exist in PostgreSQL — do not recreate via migrations unless asked)

#### `topics`
| Column | Type | Notes |
|--------|------|-------|
| id | SERIAL PK | |
| name | TEXT NOT NULL | |
| type | TEXT NOT NULL | `project`, `process`, `area`, or `others` |
| icon | TEXT | optional |
| color | TEXT | optional |
| parent_id | INTEGER FK → topics | optional; enables nesting |
| created_at | TIMESTAMP | set on insert |

#### `files`
| Column | Type | Notes |
|--------|------|-------|
| id | SERIAL PK | |
| topic_id | INTEGER FK → topics | |
| name | TEXT NOT NULL | |
| type | TEXT NOT NULL | e.g. `overview`, `plan`, `doc`, `data`, `tasks`, `protocol` |
| order_index | INTEGER | used for sort order within a topic |
| is_main | BOOLEAN | optional; when set, overrides frontend default main/secondary visibility |
| created_at | TIMESTAMP | |

#### `blocks`
| Column | Type | Notes |
|--------|------|-------|
| id | SERIAL PK | |
| file_id | INTEGER FK → files | |
| type | TEXT NOT NULL | e.g. `text`, `task`, `header`, `image`, `table`, `measurement` |
| content | JSONB NOT NULL DEFAULT `{}` | arbitrary JSON; see image blocks below |
| order_index | INTEGER | used for sort order within a file |
| created_at | TIMESTAMP | |

#### `tasks`
| Column | Type | Notes |
|--------|------|-------|
| id | SERIAL PK | |
| block_id | INTEGER FK → blocks | |
| title | TEXT NOT NULL | |
| status | TEXT DEFAULT `active` | e.g. `active`, `done` |
| due_date | TIMESTAMP | optional |
| created_at | TIMESTAMP | |

#### `task_views`
| Column | Type | Notes |
|--------|------|-------|
| id | SERIAL PK | |
| task_id | INTEGER FK → tasks | |
| view_type | TEXT NOT NULL | `arrangements`, `tasks`, `weekly`, `monthly`, `quarterly` |

#### `parts` (project topics)
| Column | Type | Notes |
|--------|------|-------|
| id | SERIAL PK | |
| topic_id | INTEGER FK → topics | |
| name | TEXT NOT NULL | |
| order_index | INTEGER | canonical order within topic |
| archived_at | TIMESTAMP | soft archive |
| created_at | TIMESTAMP | |

`blocks.part_id` optionally references `parts.id`. Part headers in `plan`, `execution`, and `tasks` files link blocks to a part.

---

## Critical business rules

### Tasks are canonical

- A task exists **once** in `tasks`.
- `task_views` only references `tasks.id` — it does not duplicate task data.
- To mark a task done from any view, `PATCH /tasks/<id>` with `{"status": "done"}`. This updates the single `tasks` row and reflects everywhere.
- Do **not** add per-view status columns. Views are membership/filtering, not state.

### Blocks content is flexible JSONB

- `blocks.content` accepts any valid JSON object.
- PATCH replaces `content` entirely when the field is sent (no deep merge).
- Image blocks store metadata in `content`:

```json
{
  "image_path": "/images/example_abc12345.jpg",
  "filename": "example_abc12345.jpg"
}
```

Upload via `POST /upload-image`, then save the returned `image_path` into the block's `content`.

### Ordering

- `files` and `blocks` list endpoints sort by `order_index` then `id`.
- `topics` and `tasks` sort by `id` only.

### No ORM migrations

The database schema already exists on Render. Models map to existing tables. Do not call `db.create_all()` in production code. Schema changes require manual SQL on Render or an explicit migration request.

---

## Code conventions

### Adding a new endpoint

1. Add or extend the model in `models.py` with a `to_dict()` method.
2. Create or extend a blueprint in `routes/`.
3. Register the blueprint in `routes/__init__.py`.
4. Use helpers from `routes/helpers.py`:
   - `get_or_404(model, id)` — fetch or 404
   - `apply_updates(instance, data, allowed_fields, datetime_fields)` — PATCH logic
   - `parse_datetime(value)` — ISO string → datetime

### Serialization

Every model has `to_dict()` returning JSON-safe primitives. Datetimes use `.isoformat()`. Do not return raw SQLAlchemy objects from routes.

### PATCH semantics

Partial updates only — fields omitted from the request body are left unchanged. To clear a nullable field, send `null` explicitly.

### Naming collision

The `File` model maps to the `files` table. It shadows Python's built-in `file` type name — always import as `from models import File`.

### Error handling

Registered in `routes/helpers.py`:
- `HTTPException` → JSON with original status code
- `ValueError` → 400
- Generic `Exception` → 500 + `db.session.rollback()`

Do not expose stack traces or internal details in API responses.

### CORS

`CORS(app)` is applied globally with default settings (all origins). Tighten only if explicitly requested.

---

## What to avoid

- **Do not modify `CONSTITUTION.md`** — read it for direction; ask the user if changes seem needed.
- **Do not add authentication** unless the user explicitly asks.
- **Do not build frontend code** in backend tasks.
- **Do not call `db.create_all()`** — tables already exist.
- **Do not duplicate task state** in `task_views`.
- **Do not store uploaded image bytes in PostgreSQL** — use the disk upload flow.
- **Do not commit secrets** — `DATABASE_URL` should come from environment in production; the fallback in `config.py` is for Render-internal dev convenience only.

---

## Common extension tasks

| Task | Where to change |
|------|-----------------|
| Add a new block type | Frontend + optionally document expected `content` shape; backend needs no change (JSONB is schemaless) |
| Add filtering/query params to list endpoints | Extend the relevant `routes/*.py` list handler |
| Add cascade delete behavior | Add explicit delete logic in route handlers or DB constraints (not currently implemented) |
| Add pagination | Extend list endpoints with `limit`/`offset` query params |
| Add auth | New middleware/decorator in `app.py`; out of scope until requested |
| Add DB migrations | Introduce Alembic; not set up yet |

---

## Quick verification

```bash
curl http://localhost:5001/health
curl http://localhost:5001/topics
curl -X POST http://localhost:5001/topics \
  -H "Content-Type: application/json" \
  -d '{"name":"Test","type":"area"}'
curl -X POST http://localhost:5001/upload-image \
  -F "image=@/path/to/photo.jpg"
```

---

## Frontend integration notes

The Flutter app in `system_app_front_end/` should:

- Point its API base URL to the deployed Render service (or `http://localhost:5001` in dev).
- Use `image_path` from upload responses as the `src` for image blocks (relative to API base URL).
- Load view-specific task lists via `GET /tasks/view/<view_type>`.
- Update task status via `PATCH /tasks/<id>`, not through `task_views`.
