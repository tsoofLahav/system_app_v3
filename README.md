# system_app

Monorepo for the personal productivity app.

**Start with [`DEVELOPMENT.md`](DEVELOPMENT.md)** — v3 status, deploy loop, and the area map.

## Layout

| Path | Purpose |
|------|---------|
| [`DEVELOPMENT.md`](DEVELOPMENT.md) | Working notes for the coding agent, incl. remembered decisions |
| [`AGENTS.md`](AGENTS.md) | Agent entry point and area routing |
| [`CONSTITUTION.md`](CONSTITUTION.md) | Product principles (read-only) |
| [`content/`](content/) | DB-bound app content, e.g. the production agent's prompt — not dev docs |
| `system_app_back_end/` | Flask REST API (Render) |
| `system_app_front_end/` | Flutter desktop / mobile client |

## Code is organized by area

Both projects split code into `areas/`, each with an `AREA.md` owning its rules:

**files** · **production_agent** · **automations** · **objects** (incl. tasks) · **ui** and **ux** (frontend only)

Maps: [backend areas](system_app_back_end/areas/README.md) · [frontend areas](system_app_front_end/lib/areas/README.md)

## Render

Set **Root Directory** to `system_app_back_end`; keep the existing build/start commands (`gunicorn`).

A separate Cron Job service runs `python scripts/run_automations.py` every minute — see [automations](system_app_back_end/areas/automations/AREA.md).

## Local dev

```bash
# Backend
cd system_app_back_end && python app.py

# Frontend
cd system_app_front_end && flutter run -d macos
```

## Tests

```bash
cd system_app_back_end && python -m pytest
cd system_app_front_end && dart analyze lib
```
