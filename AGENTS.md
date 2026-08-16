# AGENTS.md

System App is a **document-centric** productivity app: **Topic → File → continuous text with embedded objects**.

**Start here:** [`DEVELOPMENT.md`](DEVELOPMENT.md) — how we work, v3 status, deploy loop, area map, and an index of every other doc. Situational rules live in [`NOTES.md`](NOTES.md).

## Code is organized by area

Both projects use `areas/<area>/`, and each area has an `AREA.md` that is the source of truth for its rules.

| Area | Backend | Frontend |
|------|---------|----------|
| File structure & functionality | [`areas/files/`](system_app_back_end/areas/files/AREA.md) | [`areas/files/`](system_app_front_end/lib/areas/files/AREA.md) |
| Production agent | [`areas/production_agent/`](system_app_back_end/areas/production_agent/AREA.md) | [`areas/production_agent/`](system_app_front_end/lib/areas/production_agent/AREA.md) |
| Automations | [`areas/automations/`](system_app_back_end/areas/automations/AREA.md) | [`areas/automations/`](system_app_front_end/lib/areas/automations/AREA.md) |
| Objects (incl. tasks) | [`areas/objects/`](system_app_back_end/areas/objects/AREA.md) | [`areas/objects/`](system_app_front_end/lib/areas/objects/AREA.md) |
| UI — visual style | — | [`areas/ui/`](system_app_front_end/lib/areas/ui/AREA.md) |
| UX — flow and experience | — | [`areas/ux/`](system_app_front_end/lib/areas/ux/AREA.md) |

Read the relevant `AREA.md` before changing that area, and update it in the same commit.

## Domain

- **Workspace** — top container (single default from bootstrap)
- **Topic** — holds files; tagged with user-defined tags
- **File** — one continuous document stored as v4 marker text (`%%system_app_document v4`) in `files.document_json`
- **Object** — embedded task list, info piece, image, or graph
- **View** — user-created task list; membership only, never a copy
- **Automation** — a saved agent run on a schedule

## Two different agents

| Agent | Instructions |
|-------|--------------|
| **Coding agent** (Cursor) | [`DEVELOPMENT.md`](DEVELOPMENT.md) + `AREA.md` files. Before editing the file editor / embeds / `AppState` notify paths, read [**Editor keyboard safety**](NOTES.md#editor-keyboard-safety) in `NOTES.md` (avoids `KeyDownEvent … already pressed`). |
| **Production agent** (in-app AI) | `agent_configs.system_prompt` in the DB, sourced from [`content/production_agent/system_prompt.md`](content/production_agent/system_prompt.md) |

## Read-only

[`CONSTITUTION.md`](CONSTITUTION.md) defines product purpose and principles. Never edit it — ask the user if it seems outdated.
