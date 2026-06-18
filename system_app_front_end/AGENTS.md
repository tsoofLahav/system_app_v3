# system_app Frontend Guide

Read this before making frontend changes.

## Read First

- Read [`../CONSTITUTION.md`](../CONSTITUTION.md) before planning or making large changes.
- `CONSTITUTION.md` is read-only for agents.

## Operating Model (Required)

- Use a document-driven flow for non-trivial changes:
  1. Update the relevant `README.md`/`AGENTS.md`.
  2. Implement code to match the updated docs.
- Keep docs concise and current. Prefer replacing stale lines over appending new ones.
- Avoid repeating the same guidance across files; link to the most local doc instead.
- Commit after a small set of coherent changes for safer rollback when debugging.

## Definition Of Done For Docs

- The nearest folder doc explains purpose, ownership, key flows, and extension rules.
- Any changed behavior has exactly one source-of-truth description.
- Cross-links point to the right local docs.
- Stale statements are removed, not preserved for history.

## Documentation Map

- Frontend root overview: [`README.md`](README.md)
- Code structure overview: [`lib/README.md`](lib/README.md)
- Core state/data layer: [`lib/core/README.md`](lib/core/README.md)
- Feature modules: [`lib/features/README.md`](lib/features/README.md)
- Shared UI primitives: [`lib/shared/README.md`](lib/shared/README.md)
- Design system: [`lib/design_system/README.md`](lib/design_system/README.md)

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

- Backend API and contracts: [`../AGENTS.md`](../AGENTS.md)

## Local Run

```bash
cd system_app_front_end
flutter pub get
flutter run -d macos
```
