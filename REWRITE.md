# System App v2 Rewrite

Greenfield architecture rewrite — **no migration from v1**.

## Status

| Phase | Status |
|-------|--------|
| 0 — Document spike + schema + API | Done |
| 1 — Shell + topics + documents | Done |
| 2 — Embedded tasks + document editor | Done |
| 3 — User views + tags | Done |
| 4 — Generic agent + tools | Done |
| 5 — Text diff + DB automations | Done |
| 6 — Legacy cleanup | Done |

## Fresh database

```bash
dropdb system_app  # if needed
createdb system_app
psql system_app -f system_app_back_end/migrations/001_v2_schema.sql
cd system_app_back_end && flask run
```

Bootstrap on first launch: `POST /bootstrap` (called automatically by the Flutter app).

## Key docs

- [`system_app_back_end/docs/DOCUMENT_MODEL.md`](system_app_back_end/docs/DOCUMENT_MODEL.md)
- [`system_app_back_end/docs/API.md`](system_app_back_end/docs/API.md)
