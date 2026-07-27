# system_app Frontend Guide

Read [`../DEVELOPMENT.md`](../DEVELOPMENT.md) first for v3 status and the area map, then [`../AGENTS.md`](../AGENTS.md) for monorepo orientation.

## Code is organized by area

| Area | Doc |
|------|-----|
| File structure & functionality | [`lib/areas/files/AREA.md`](lib/areas/files/AREA.md) |
| Production agent | [`lib/areas/production_agent/AREA.md`](lib/areas/production_agent/AREA.md) |
| Automations | [`lib/areas/automations/AREA.md`](lib/areas/automations/AREA.md) |
| Objects (incl. tasks) | [`lib/areas/objects/AREA.md`](lib/areas/objects/AREA.md) |
| UI — visual style | [`lib/areas/ui/AREA.md`](lib/areas/ui/AREA.md) |
| UX — flow and experience | [`lib/areas/ux/AREA.md`](lib/areas/ux/AREA.md) |

Area map: [`lib/areas/README.md`](lib/areas/README.md) · Folder overview: [`lib/README.md`](lib/README.md)

**UI is what it looks like. UX is what happens and where things live.** Neither means "the whole frontend".

## Operating model

1. Read the relevant `AREA.md`.
2. Change the code.
3. Update that `AREA.md` in the same commit — and its backend twin if the behavior spans both.

Keep exactly one source of truth per behavior. Replace stale lines rather than appending.

## Other docs

| Topic | Doc |
|-------|-----|
| Rich text span invariants | [`lib/areas/files/rich_text/RICH_TEXT.md`](lib/areas/files/rich_text/RICH_TEXT.md) |
| Bilingual / RTL | [`lib/core/l10n/BILINGUAL.md`](lib/core/l10n/BILINGUAL.md) |
| Backend API | [`../system_app_back_end/docs/API.md`](../system_app_back_end/docs/API.md) |
| Product principles (read-only) | [`../CONSTITUTION.md`](../CONSTITUTION.md) |

## Local run

```bash
cd system_app_front_end
flutter pub get
flutter run -d macos
```
