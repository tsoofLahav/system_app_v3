# API Reference

REST API for `system_app`. For domain model and conventions, see [`../AGENTS.md`](../AGENTS.md).

All endpoints return JSON. Timestamps are ISO 8601 strings (e.g. `"2026-06-09T10:00:00"`).

## Error format

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

## Health

| Method | Path | Response |
|--------|------|----------|
| GET | `/health` | `{"status": "ok"}` |

---

## Topics

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

## Files

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
  "order_index": 0,
  "is_main": true
}
```

**PATCH body** — any subset of: `topic_id`, `name`, `type`, `order_index`, `is_main`

---

## Blocks

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

**PATCH body** — any subset of: `file_id`, `type`, `content`, `order_index`, `part_id`

`part_id` links a block to a project part. Send `null` to clear.

---

## Parts

| Method | Path | Description |
|--------|------|-------------|
| GET | `/topics/<topic_id>/parts` | List ordered parts |
| POST | `/topics/<topic_id>/parts` | Create part (optional placement) |
| GET | `/parts/<id>` | Get one |
| PATCH | `/parts/<id>` | Update `name`, `order_index`, `archived_at` |
| DELETE | `/parts/<id>` | Archive part |
| POST | `/files/<file_id>/parts` | Place new or existing part in file |
| GET | `/files/<file_id>/part-ids` | Part ids placed in file |

**POST `/files/<file_id>/parts`** — existing part: `{"part_id": 3}`; new part: `{"name": "Auth"}`; optional `insert_after_block_id`.

---

## Tasks

| Method | Path | Description |
|--------|------|-------------|
| GET | `/tasks` | List all |
| GET | `/tasks/<id>` | Get one |
| GET | `/blocks/<block_id>/tasks` | Tasks for a block |
| GET | `/tasks/view/<view_type>` | Tasks joined with task_views (see below) |
| POST | `/tasks` | Create |
| PATCH | `/tasks/<id>` | Partial update |
| DELETE | `/tasks/<id>` | Delete |

**POST body** (required: `title` field; value may be `""` for a blank task row):

```json
{
  "block_id": 1,
  "title": "Buy paint",
  "status": "active",
  "due_date": "2026-06-15T09:00:00"
}
```

Empty string titles are valid. The field must be present; omitting `title` returns 400.

**PATCH body** — any subset of: `block_id`, `title`, `status`, `due_date`

### `GET /tasks/view/<view_type>`

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

## Task views

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

## Image upload & serving

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
