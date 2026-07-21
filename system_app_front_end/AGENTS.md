# system_app Frontend Guide

Read this before making frontend changes. Start at [`../AGENTS.md`](../AGENTS.md) for monorepo orientation and the full task-routing table.

## Read First

- Read [`../CONSTITUTION.md`](../CONSTITUTION.md) before planning or making large changes.
- `CONSTITUTION.md` is read-only for agents.

## Operating Model (Required)

- Use a document-driven flow for non-trivial changes:
  1. Update the relevant `README.md`/`AGENTS.md`.
  2. Implement code to match the updated docs.
- Keep docs concise and current. Prefer replacing stale lines over appending new ones.
- Avoid repeating the same guidance across files; link to the most local doc instead.
- Commit after each feature is done — see [`../AGENTS.md`](../AGENTS.md) git workflow.

## Definition Of Done For Docs

- The nearest folder doc explains purpose, ownership, key flows, and extension rules.
- Any changed behavior has exactly one source-of-truth description.
- Cross-links point to the right local docs.
- Stale statements are removed, not preserved for history.

## Task routing (frontend)

| If you are changing… | Read first | Key code |
|---|---|---|
| Project parts | [`lib/features/blocks/PARTS.md`](lib/features/blocks/PARTS.md) | `part_service.dart`, `part_dialogs.dart`, `app_state.dart` |
| Block editing/rendering | [`lib/features/blocks/README.md`](lib/features/blocks/README.md) | `block_renderer.dart`, `app_state.dart` |
| Task rows / zones | [`lib/features/tasks/TASK_FILES.md`](lib/features/tasks/TASK_FILES.md) | `task_zone_list.dart`, `app_state_task_file.dart` |
| Details blocks | [`lib/features/blocks/DETAILS.md`](lib/features/blocks/DETAILS.md) | `details_block_widget.dart`, `details_lookup.py` |
| Task views / sections | [`lib/features/task_view/README.md`](lib/features/task_view/README.md) | `task_view_pane.dart`, `app_state.dart` |
| Topic layout / reorder | [`lib/features/topic/README.md`](lib/features/topic/README.md) + runbooks | `topic_view.dart`, `file_layout_board.dart` |
| Archive browse | [`lib/features/archive/README.md`](lib/features/archive/README.md) | `archive_topic_view.dart`, `archive_file_grid.dart` |
| Shell / global controls | [`lib/features/shell/README.md`](lib/features/shell/README.md) | `app_shell.dart`, `app_state.dart` |
| Sidebar navigation | [`lib/features/sidebar/README.md`](lib/features/sidebar/README.md) | `app_sidebar.dart`, `app_state.dart` |
| Bilingual / RTL | [`lib/core/l10n/BILINGUAL.md`](lib/core/l10n/BILINGUAL.md) | `app_strings.dart` |

## Subsystem index

| Topic | Doc |
|-------|-----|
| AI context and tool requests | [`lib/core/ai/README.md`](lib/core/ai/README.md) |
| Automation UI and companion flows | [`docs/runbooks/automation-mechanism.md`](docs/runbooks/automation-mechanism.md) |
| Change review dialog | [`lib/shared/change_review/README.md`](lib/shared/change_review/README.md) |
| Backend automation (execution) | [`../system_app_back_end/docs/automation.md`](../system_app_back_end/docs/automation.md) |
| Backend API | [`../system_app_back_end/docs/API.md`](../system_app_back_end/docs/API.md) |
| Topic task files (persistence) | [`../system_app_back_end/docs/TASKS.md`](../system_app_back_end/docs/TASKS.md) |

## Documentation Map

- Frontend root overview: [`README.md`](README.md)
- Code structure overview: [`lib/README.md`](lib/README.md)
- Core state/data layer: [`lib/core/README.md`](lib/core/README.md)
- Feature modules: [`lib/features/README.md`](lib/features/README.md)
- Shared UI primitives: [`lib/shared/README.md`](lib/shared/README.md)
- Design system (visual contract, glass presets, spacing): [`lib/design_system/README.md`](lib/design_system/README.md)
- Bilingual / RTL rules (English + Hebrew): [`lib/core/l10n/BILINGUAL.md`](lib/core/l10n/BILINGUAL.md)

Use folder-local `README.md` files as the source of truth for that folder.

## Anti-Duplication Rule

- Root docs (`AGENTS.md`, `README.md`) define workflow and navigation only.
- Folder docs define local behavior and contracts.
- Runbooks define step-by-step reconstruction flows.
- Do not describe the same behavior in more than one layer; link to the owner doc.

## Maintenance Checklist

- If behavior changes, update the nearest doc in the same change set.
- If structure changes, update the affected folder map/docs immediately.
- If a rule moves, replace old references with links to the new source.
- Keep commit size small enough to revert without losing unrelated work.

## Related

- Monorepo entry: [`../AGENTS.md`](../AGENTS.md)
- Backend workflow and domain model: [`../system_app_back_end/AGENTS.md`](../system_app_back_end/AGENTS.md)

## Local Run

```bash
cd system_app_front_end
flutter pub get
flutter run -d macos
```
