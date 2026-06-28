# `shared/widgets/`

Purpose: composable reusable widgets used across feature modules.

Typical contents:
- Generic rows/cards/chips used by more than one feature.
- Reorder helpers and wrappers used across topic/task flows.
- Small interaction primitives (icons, disclosure helpers, wrappers).

Standards:
- Keep inputs explicit and minimal.
- Avoid direct dependencies on one feature's private state shape.
- If usage narrows to one feature, move it back to that feature folder.

## Context menus (`app_context_menu.dart`)

Glass-style bubble menus (outline + shadow + blur) used for file/block right-click. **Do not** use Material `showMenu` for new menus — extend `AppContextMenu` instead.

| Piece | Role |
|---|---|
| `AppContextMenu.show` | Custom overlay; pass `isRtl: strings.isRtl` (do not rely on overlay inheriting `Directionality`) |
| `AppContextMenuSubmenu` | Hover row with side bubble (e.g. **Add block →** insert types) |
| `AppContextMenuItem` / `AppContextMenuDivider` | Action rows and separators |

**RTL submenu chevron:** use `DisclosureIcon` (same as sidebar sections) — trailing in the row (`[label, chevron]`), Lucide `chevronRight` + `Transform.flip` when `Directionality` is RTL. Do not hand-pick Material chevrons or flip without matching row order; submenu opens to the left in Hebrew.

**Submenu layout:** main panel stays at `left: 0`; in RTL the side bubble is to its left and the main panel shifts right when open.

**Submenu hit target:** the overlay host height must include `rowTop + submenuHeight` (not just `max(main, submenu)`), so lower submenu rows (e.g. **Custom color…**) stay hoverable. An invisible bridge spans the gap between main and side panels.

## Disclosure chevrons (`disclosure_icon.dart`)

Shared RTL-safe expand/submenu arrow. Reuse anywhere a row opens a nested panel (sidebar sections, context submenu rows, task assign menu uses the same flip pattern with `AppIcons.chevronRight`).
