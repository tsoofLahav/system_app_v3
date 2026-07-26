# AGENTS.md (v2)

System App is a **document-centric** productivity app: **Topic → File → text body + embedded objects**.

## Domain

- **Workspace** — top container (single default in bootstrap)
- **Topic** — tagged with user-defined **tags** (replaces hardcoded topic types)
- **File** — plain text `body` with inline markers `{{task:id}}`, `{{info:id}}`
- **Object** — embed row linking file body to **Task** or **InformationPiece**
- **View** — user-created task panes with **view_task_memberships**
- **Automation** — DB row → same **agent** pipeline as manual AI runs

See [`system_app_back_end/docs/DOCUMENT_MODEL.md`](system_app_back_end/docs/DOCUMENT_MODEL.md).

## AI

One tool-using agent: `POST /agent/run` with `scope`, `apply_mode` (`direct_apply` | `review` | `notify_only`).

Review uses deterministic **text diff** on full body snapshots (`POST /files/:id/diff`).

## Frontend

Preserve **design_system** and **shell** chrome. Topic content is **`DocumentPane`** + **`DocumentEditor`**.

State: `AppState` (v2) with topic/file/view services — no block or file-type registries.

## Database

Greenfield only: apply [`system_app_back_end/migrations/001_v2_schema.sql`](system_app_back_end/migrations/001_v2_schema.sql).

Track rewrite progress in [`REWRITE.md`](REWRITE.md).
