# Frontend areas

Each area owns its widgets, data, and an `AREA.md` describing its rules and logic.

| Area | Folder | Doc | Backend twin |
|------|--------|-----|--------------|
| File structure & functionality | [`files/`](files/) | [`files/AREA.md`](files/AREA.md) | [backend files](../../../system_app_back_end/areas/files/AREA.md) |
| Production agent | [`production_agent/`](production_agent/) | [`production_agent/AREA.md`](production_agent/AREA.md) | [backend agent](../../../system_app_back_end/areas/production_agent/AREA.md) |
| Automations | [`automations/`](automations/) | [`automations/AREA.md`](automations/AREA.md) | [backend automations](../../../system_app_back_end/areas/automations/AREA.md) |
| Objects (incl. tasks) | [`objects/`](objects/) | [`objects/AREA.md`](objects/AREA.md) | [backend objects](../../../system_app_back_end/areas/objects/AREA.md) |
| UI — visual style | [`ui/`](ui/) | [`ui/AREA.md`](ui/AREA.md) | — frontend only |
| UX — flow and experience | [`ux/`](ux/) | [`ux/AREA.md`](ux/AREA.md) | — frontend only |

## UI vs UX

These two are easy to confuse, so the line is strict:

| | UI | UX |
|---|-----|-----|
| Answers | *What does it look like?* | *What happens, and where do things live?* |
| Owns | Colors, fonts, button/toggle/dialog design, glass, spacing | Layout of files, section switching, sidebar, menus, shortcuts |
| Example | The glass surface used by every dialog | Which dialog opens, and from where |

Neither means "the whole frontend folder". In-file embed presentation belongs to **files**; task **views** / info **links** and object data belong to **objects**; a widget that decides *where* a view appears belongs to **ux**; the color it is painted comes from **ui**.

## Outside the areas

| Path | Why it is shared |
|------|------------------|
| `core/app_state.dart` | Single app-wide state object; delegates to area services |
| `core/services/api_service.dart` | HTTP client used by every area service |
| `core/l10n/` | Bilingual English/Hebrew strings and RTL rules |
| `core/platform/` | Form-factor detection (desktop vs phone) |
| `shared/utils/` | Clipboard, image picking, platform text helpers |
| `config/` | API base URL |

## Rules

- An area may import `core`, `shared`, `ui`, and other areas' data — but keep widget dependencies one-directional where possible.
- Every visual constant comes from `ui/`. No hardcoded colors, font sizes, or radii elsewhere.
- Change behavior → update that area's `AREA.md` in the same commit.
