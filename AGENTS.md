# system_app — Agent Guide

Monorepo entry for AI agents. Read this first, then the sub-guide for your area.

## Orientation

**system_app** is a personal productivity app — an external memory and organization layer for thoughts, projects, processes, and life admin.

| Path | Stack | Role |
|------|-------|------|
| [`system_app_back_end/`](system_app_back_end/) | Flask + PostgreSQL (Render) | REST API — CRUD, uploads, AI, automations |
| [`system_app_front_end/`](system_app_front_end/) | Flutter (desktop-first) | Most behavior and UX |
| [`CONSTITUTION.md`](CONSTITUTION.md) | — | Product philosophy (read-only for agents) |

There is **no authentication** yet. Do not add auth unless explicitly requested.

## Constitution summary

Read [`CONSTITUTION.md`](CONSTITUTION.md) before large changes. Key principles:

- **Capture first** — record thoughts immediately; classify later
- **Progressive disclosure** — show only what is relevant now
- **Context over quantity** — summaries and active actions beat full history
- **Frontend-heavy** — implement behavior in Flutter when reasonable
- **Generic backend** — backend stores and serves; FE owns UX logic
- **Topics → Files → Blocks → Tasks** — the core hierarchy
- **Tasks are canonical** — one task row, many views via `task_views`
- **Simplicity over features** — clarity beats feature count

## Read order

1. This file — pick your task from the routing table
2. Sub-guide — [`system_app_front_end/AGENTS.md`](system_app_front_end/AGENTS.md) or [`system_app_back_end/AGENTS.md`](system_app_back_end/AGENTS.md)
3. Nearest folder `README.md` — behavior source of truth for that area
4. Deep reference only if needed — API docs, runbooks, subsystem docs

## Task routing

| If you are changing… | Read first | Key code |
|---|---|---|
| Project parts | [`system_app_front_end/lib/features/blocks/PARTS.md`](system_app_front_end/lib/features/blocks/PARTS.md) | `part_service.dart`, `routes/parts.py`, `part_placement.py` |
| Block editing/rendering | [`system_app_front_end/lib/features/blocks/README.md`](system_app_front_end/lib/features/blocks/README.md) | `block_renderer.dart`, `app_state.dart` |
| Task rows / zones | [`system_app_front_end/lib/features/tasks/README.md`](system_app_front_end/lib/features/tasks/README.md) | `task_lines_editor.dart`, `app_state.dart` |
| Task views / sections | [`system_app_front_end/lib/features/task_view/README.md`](system_app_front_end/lib/features/task_view/README.md) | `task_view_pane.dart`, `app_state.dart` |
| Topic layout / reorder | [`system_app_front_end/lib/features/topic/README.md`](system_app_front_end/lib/features/topic/README.md) + runbooks | `topic_view.dart`, `file_layout_board.dart` |
| Archive browse | [`system_app_front_end/lib/features/archive/README.md`](system_app_front_end/lib/features/archive/README.md) | `archive_topic_view.dart`, `archive_file_grid.dart` |
| Shell / global controls | [`system_app_front_end/lib/features/shell/README.md`](system_app_front_end/lib/features/shell/README.md) | shell widgets, `app_state.dart` |
| Sidebar navigation | [`system_app_front_end/lib/features/sidebar/README.md`](system_app_front_end/lib/features/sidebar/README.md) | sidebar widgets, `app_state.dart` |
| API / persistence | [`system_app_back_end/AGENTS.md`](system_app_back_end/AGENTS.md) | `models.py`, `routes/` |
| Automation (backend) | [`system_app_back_end/docs/automation.md`](system_app_back_end/docs/automation.md) | `services/automation_*.py` |
| Automation (UI) | [`system_app_front_end/docs/runbooks/automation-mechanism.md`](system_app_front_end/docs/runbooks/automation-mechanism.md) | `automation_service.dart`, shell automation menu |
| Project update from log | [`system_app_front_end/docs/runbooks/project-update-automation.md`](system_app_front_end/docs/runbooks/project-update-automation.md) | `ai_smart_update/`, `project_update_batch_dialog.dart` |
| AI proposals / context | [`system_app_front_end/lib/core/ai/README.md`](system_app_front_end/lib/core/ai/README.md) | `ai_proposal_service.dart`, `routes/ai*.py` |
| Change review UI | [`system_app_front_end/lib/shared/change_review/README.md`](system_app_front_end/lib/shared/change_review/README.md) | `change_review_dialog.dart` |
| Bilingual / RTL | [`system_app_front_end/lib/core/l10n/BILINGUAL.md`](system_app_front_end/lib/core/l10n/BILINGUAL.md) | `app_strings.dart` |

## Sub-guides

- **Frontend:** [`system_app_front_end/AGENTS.md`](system_app_front_end/AGENTS.md) — workflow, doc map, FE routing
- **Backend:** [`system_app_back_end/AGENTS.md`](system_app_back_end/AGENTS.md) — domain model, conventions, subsystem links
- **API reference:** [`system_app_back_end/docs/API.md`](system_app_back_end/docs/API.md) — endpoints, config, deployment

## Folder README template

Every folder `README.md` should cover:

```
Purpose → Key files (table) → Inputs/deps → Main flows → Side effects → Extension rules → Runbook/links
```

Nearest folder doc owns behavior. Root and sub `AGENTS.md` files link only — do not duplicate behavior descriptions.

## Git workflow

- Work on **`main`** — no feature branches.
- **Commit after each feature** is done, for quick rollback. Frontend-only work is committed at feature completion; backend work is usually committed earlier (see below).
- **Push backend changes** whenever you change `system_app_back_end/` so Render deploys and the Flutter app can test against the live API. Commit and push together when the backend change is ready to test.

## Local dev

```bash
# Backend
cd system_app_back_end && python app.py

# Frontend
cd system_app_front_end && flutter run -d macos
```
