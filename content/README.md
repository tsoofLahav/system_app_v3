# Content (database-bound)

Files here are **not developer documentation**. They are edited in git and **synced into PostgreSQL** for the running app.

| Path | DB destination | Sync |
|------|----------------|------|
| [`production_agent/system_prompt.md`](production_agent/system_prompt.md) | `agent_configs.system_prompt` | `python system_app_back_end/scripts/sync_agent_prompt.py --overwrite` |

**Developer docs** live elsewhere:

- Shared v3 work: [`DEVELOPMENT.md`](../DEVELOPMENT.md)
- Backend API/code: [`system_app_back_end/docs/`](../system_app_back_end/docs/)
- Frontend editor: [`system_app_front_end/lib/areas/files/AREA.md`](../system_app_front_end/lib/areas/files/AREA.md)
