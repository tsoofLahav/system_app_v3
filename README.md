# system_app

Monorepo for the personal productivity app.

| Path | Purpose |
|------|---------|
| `system_app_back_end/` | Flask REST API (deployed on Render) |
| `system_app_front_end/` | Flutter desktop/mobile client |
| `CONSTITUTION.md` | Product principles (read-only for agents) |

## Render

Set **Root Directory** to `system_app_back_end` and keep the existing build/start commands (`gunicorn`, etc.).

## Local dev

```bash
# Backend
cd system_app_back_end && python app.py

# Frontend
cd system_app_front_end && flutter run
```
