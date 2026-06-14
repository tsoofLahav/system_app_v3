# system_app — Backend Agent Guide

This document is for AI agents and developers working on the **system_app** backend. Read it before making changes.

## Constitution (read first)

Before any backend work, read [`../CONSTITUTION.md`](../CONSTITUTION.md). It defines the app's purpose, philosophy, UX principles, and architectural direction. Implementation must align with it.

**Do not modify `CONSTITUTION.md`.** It is read-only for agents. If something seems outdated or conflicting, stop and ask the user — never edit that file yourself.

## Project overview

**system_app** is a personal productivity app. The backend is a REST API built with Flask. The Flutter frontend lives in `system_app_front_end/` and consumes this API. There is **no authentication** yet — do not add auth unless explicitly requested.

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
system_app/
├── CONSTITUTION.md        # App purpose & philosophy (read-only for agents)
├── system_app_back_end/   # Flask API (this folder)
│   ├── app.py             # Flask app factory + health check; entry point
│   ├── config.py          # DATABASE_URL, UPLOAD_FOLDER
│   ├── models.py          # SQLAlchemy models + to_dict() serializers
│   ├── requirements.txt
│   ├── Procfile           # web: gunicorn app:app
│   ├── AGENTS.md          # this file
│   └── routes/
│       ├── __init__.py    # register_blueprints()
│       ├── helpers.py     # shared CRUD helpers + error handlers
│       ├── topics.py
│       ├── files.py
│       ├── blocks.py
│       ├── tasks.py
│       ├── task_views.py
│       └── upload.py
└── system_app_front_end/  # Flutter app (separate; do not modify from backend tasks)
```

---

## Domain model

The app organizes work as a hierarchy:

```
Topic (project / process / area)
  └── File (overview / plan / doc / data / tasks / protocol …)
        └── Block (text / task / header / image / table / measurement …)
              └── Task (optional; task-type blocks link here)
```

Tasks can also appear in multiple **views** via the `task_views` join table.

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
| type | TEXT NOT NULL | `project`, `process`, or `area` |
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

## API reference

All endpoints return JSON. Timestamps are ISO 8601 strings (e.g. `"2026-06-09T10:00:00"`).

### Error format

```json
{"error": "description"}
```

| Status | When |
|--------|------|
| 400 | Validation error, bad datetime, missing required fields |
| 404 | Resource not found |
| 500 | Unexpected server error (DB failures, etc.) |

Successful DELETE returns `204` with empty body.

---

### Health

| Method | Path | Response |
|--------|------|----------|
| GET | `/health` | `{"status": "ok"}` |

---

### Topics

| Method | Path | Description |
|--------|------|-------------|
| GET | `/topics` | List all |
| GET | `/topics/<id>` | Get one |
| POST | `/topics` | Create |
| PATCH | `/topics/<id>` | Partial update |
| DELETE | `/topics/<id>` | Delete |

**POST body** (required: `name`, `type`):
```json
{
  "name": "Home renovation",
  "type": "project",
  "icon": "hammer",
  "color": "#FF5733",
  "parent_id": null
}
```

**PATCH body** — any subset of: `name`, `type`, `icon`, `color`, `parent_id`

---

### Files

| Method | Path | Description |
|--------|------|-------------|
| GET | `/files` | List all |
| GET | `/files/<id>` | Get one |
| GET | `/topics/<topic_id>/files` | Files for a topic |
| POST | `/files` | Create |
| PATCH | `/files/<id>` | Partial update |
| DELETE | `/files/<id>` | Delete |

**POST body** (required: `name`, `type`):
```json
{
  "topic_id": 1,
  "name": "Project plan",
  "type": "plan",
  "order_index": 0
}
```

**PATCH body** — any subset of: `topic_id`, `name`, `type`, `order_index`

---

### Blocks

| Method | Path | Description |
|--------|------|-------------|
| GET | `/blocks` | List all |
| GET | `/blocks/<id>` | Get one |
| GET | `/files/<file_id>/blocks` | Blocks for a file |
| POST | `/blocks` | Create |
| PATCH | `/blocks/<id>` | Partial update |
| DELETE | `/blocks/<id>` | Delete |

**POST body** (required: `type`):
```json
{
  "file_id": 1,
  "type": "text",
  "content": {"text": "Hello world"},
  "order_index": 0
}
```

**PATCH body** — any subset of: `file_id`, `type`, `content`, `order_index`

---

### Tasks

| Method | Path | Description |
|--------|------|-------------|
| GET | `/tasks` | List all |
| GET | `/tasks/<id>` | Get one |
| GET | `/blocks/<block_id>/tasks` | Tasks for a block |
| GET | `/tasks/view/<view_type>` | Tasks joined with task_views (see below) |
| POST | `/tasks` | Create |
| PATCH | `/tasks/<id>` | Partial update |
| DELETE | `/tasks/<id>` | Delete |

**POST body** (required: `title`):
```json
{
  "block_id": 1,
  "title": "Buy paint",
  "status": "active",
  "due_date": "2026-06-15T09:00:00"
}
```

**PATCH body** — any subset of: `block_id`, `title`, `status`, `due_date`

#### `GET /tasks/view/<view_type>`

Returns tasks that belong to a given view. Each item is the task dict plus:

```json
{
  "id": 1,
  "block_id": 5,
  "title": "Buy paint",
  "status": "active",
  "due_date": null,
  "created_at": "2026-06-09T10:00:00",
  "task_view_id": 12,
  "view_type": "weekly"
}
```

Valid `view_type` values: `arrangements`, `tasks`, `weekly`, `monthly`, `quarterly`.

Typical frontend flow:
1. `POST /tasks` — create task
2. `POST /task_views` — add to view(s)
3. `GET /tasks/view/weekly` — load weekly list
4. `PATCH /tasks/<id>` — mark done (updates everywhere)

---

### Task views

| Method | Path | Description |
|--------|------|-------------|
| GET | `/task_views` | List all |
| GET | `/task_views/<id>` | Get one |
| GET | `/task_views/by-view/<view_type>` | Filter by view_type |
| POST | `/task_views` | Create |
| PATCH | `/task_views/<id>` | Partial update |
| DELETE | `/task_views/<id>` | Delete |

**POST body** (required: `task_id`, `view_type`):
```json
{
  "task_id": 1,
  "view_type": "weekly"
}
```

**PATCH body** — any subset of: `task_id`, `view_type`

---

### Image upload & serving

| Method | Path | Description |
|--------|------|-------------|
| POST | `/upload-image` | Upload image (multipart) |
| GET | `/images/<filename>` | Serve uploaded file |

**Upload request**: `multipart/form-data` with field name `image`.

**Allowed extensions**: `png`, `jpg`, `jpeg`, `gif`, `webp`, `svg`

**Response** (201):
```json
{
  "filename": "photo_a1b2c3d4.jpg",
  "image_path": "/images/photo_a1b2c3d4.jpg",
  "url": "/images/photo_a1b2c3d4.jpg"
}
```

Filenames are sanitized with `secure_filename` and suffixed with a random 8-char hex to avoid collisions.

---

## Configuration

Defined in `config.py`:

| Variable | Default | Purpose |
|----------|---------|---------|
| `DATABASE_URL` | Render internal URL (fallback) | PostgreSQL connection string |
| `UPLOAD_FOLDER` | `/var/data/uploads` | Image storage directory |

`DATABASE_URL` is read from the environment first. Render auto-injects it when the DB is linked. The fallback URL uses Render's **internal** hostname and only works inside Render's network.

`postgres://` URLs are automatically rewritten to `postgresql://` for SQLAlchemy compatibility.

### Local development

```bash
cd system_app_back_end
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

# Use Render's EXTERNAL database URL for local access:
export DATABASE_URL="postgresql://user:pass@dpg-....oregon-postgres.render.com/dbname"

# Local uploads (Render path won't exist on Mac/Linux dev machines):
export UPLOAD_FOLDER="./uploads"

python app.py          # dev server on PORT (default 5000)
gunicorn app:app       # production-style
```

On macOS, port 5000 may be taken by AirPlay Receiver — use `PORT=5001 python app.py`.

---

## Render deployment

| Setting | Value |
|---------|-------|
| Root directory | `system_app_back_end` |
| Start command | `gunicorn app:app` (or use `Procfile`) |
| `DATABASE_URL` | Auto-set when PostgreSQL is linked |
| Persistent disk | Mount at `/var/data` for image uploads to survive redeploys |

Without a persistent disk, uploaded images are lost on redeploy.

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
| Add a new block type | Frontend + optionally document expected `content` shape here; backend needs no change (JSONB is schemaless) |
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
