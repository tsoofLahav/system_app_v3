# Area: UI — visual style

**Only how things look.** No navigation, no flows, no business rules.

Backend twin: none. This area is frontend-only.

## What belongs here

| Concern | Files |
|---------|-------|
| Colors | [`app_colors.dart`](app_colors.dart), [`app_theme.dart`](app_theme.dart) |
| Text size and font | [`app_typography.dart`](app_typography.dart) |
| Glass | [`glass_surface.dart`](glass_surface.dart) |
| Buttons, toggles, switches | [`app_segmented_toggle.dart`](app_segmented_toggle.dart), [`app_switch.dart`](app_switch.dart) |
| Dialog design | [`adaptive_dialog.dart`](adaptive_dialog.dart), [`overlay_dialog_shell.dart`](overlay_dialog_shell.dart), [`overlay_dialog_style.dart`](overlay_dialog_style.dart), [`dialog_field_style.dart`](dialog_field_style.dart) |
| Icons | [`app_icons.dart`](app_icons.dart) |
| Cards and previews | [`overlay_file_preview_card.dart`](overlay_file_preview_card.dart), [`layout_preview_icon.dart`](layout_preview_icon.dart), [`note_widgets.dart`](note_widgets.dart) |
| Carousel | [`horizontal_carousel.dart`](horizontal_carousel.dart) |
| RTL / bilingual layout primitives | [`bilingual_layout.dart`](bilingual_layout.dart) |

## Two kinds of text

The distinction matters and is easy to get wrong:

| Text | Style source |
|------|--------------|
| **App chrome** — menu labels, dialog titles, buttons, sidebar | `AppTypography` chrome styles |
| **File content** — the default text a user types in a document | `AppTypography.noteBodyStyle` and friends |

Changing document default size or font is a UI change, but it affects how every file reads — treat it as a deliberate decision, not a tweak.

## Glass

Glass is the app's signature surface: a blurred, translucent panel used for overlays, dialogs, and floating chrome. It is defined once in `glass_surface.dart`. Anything that needs to float over content uses it rather than rolling its own blur.

## Rules

- **No hardcoded visual values outside this folder.** Colors, font sizes, radii, blur amounts, and spacing constants live here.
- UI widgets are **presentational**: they take values and callbacks, never call services or `AppState`.
- Nothing here decides *when* it is shown — that is [UX](../ux/AREA.md).
- Changing a shared style means checking both app chrome and file content, since both consume this area.
- Every surface must work in English (LTR) and Hebrew (RTL); use `bilingual_layout.dart` rather than hardcoding direction.
