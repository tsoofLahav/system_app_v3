# Area: UI — visual style

**Only how things look.** No navigation, no flows, no business rules. This file is the cross-app style spec: every colour, size, and shape choice in the app should be traceable to something below.

Backend twin: none. This area is frontend-only.

## The look, in one paragraph

The app is a personal workspace, so the interface should **reduce mental load rather than ask for attention**. Calm, mature, practical, quietly colour-supported. Text is small and dense, spaces are tight, edges are soft, and nothing pulses or shouts. The user's own content is the loudest thing on screen; every piece of chrome is deliberately quieter than the file it sits next to.

Concretely, that means: small type (12–14px for almost everything), 4–18px spacing, thin borders under 1px, gentle translucent fills instead of solid blocks, and no saturated alert colours anywhere. **Dialogs and menus hug their content** — never large empty panels around a few fields (see [Dialogs and menus](#dialogs-and-menus)).

## Surface hierarchy

Loudest last:

| Surface | Treatment |
|---------|-----------|
| **Canvas** — the window behind everything | Near-white neutral gradient, with the topic's soft top wash painted full-bleed on desktop (including behind the sidebar). Phone structure is locked in UX: grey middle (`phoneCanvas`); warm off-white header and footer (`phoneStripe`). Header ombre is a light topic wash in the lower third only — not on Home or views. File card has its usual shadow; tool bubbles sit above the footer, with no lift |
| **File panes** — the working surfaces | Topic colour at a gentle strength, thin saturated topic border, card shadow. Same frames on phone and desktop |
| **View list frames** — section/topic cards on the view page | Same file-pane treatment (`NoteCard` / `filePaneDecoration`); topic frames use topic colour, section frames use optional section colour |
| **Sidebar** | Soft glass floating above the canvas — never paints the topic wash itself |
| **Floating chrome** — bottom bar, insert bar, pills | Glass or solid white with a lift shadow; insert tools stay on the bottom-bar baseline; preferences / automations sit at the start edge. Phone tools are the same bubbles on the grey middle, above the thin footer stripe, with no lift shadow. AI icons use the same 34px tap slots as the other bars |
| **Dialogs** | Glass panels over a light scrim |
| **Context menus** | The topmost layer — cooler frost, tighter rows |

## Colours

All of them live in [`app_colors.dart`](app_colors.dart). Nothing outside this folder writes a `Color(0x…)`.

### Neutrals and text

| Token | Value | Used for |
|-------|-------|----------|
| `canvasNeutralTop` / `canvasNeutralBottom` | `#FFFEFE` → `#FAFAF8` | The window gradient |
| `phoneStripe` | `#F5F3ED` | Phone header and footer stripes (warm off-white) |
| `phoneCanvas` | `#E4E2DC` | Phone middle behind the file card (a step darker) |
| `noteTop` / `noteBottom` | `#FCFBF7` → `#F4F2EC` | Untinted cards |
| `mainNoteTop` / `mainNoteBottom` | `#FFFFFF` | Panes in the main topic |
| `noteBorder` | `#DCD8CF` | Card edges |
| `noteShadow` | black 6% | Every card shadow |
| `text` | `#5E5B56` | **All** text — titles and body share one soft charcoal |
| `textHint` | `#9D988F` | Hints, meta, secondary labels |
| `sidebarBg` / `sidebarBorder` | `#F1EFE8` / `#D8D4CB` | Sidebar panel |

There is no black and no pure grey. Warm charcoal on warm off-white is what keeps long reading comfortable.

### Accents

| Token | Value | Meaning |
|-------|-------|---------|
| `primary` | `#37899E` | The app's own accent: selections, key actions, menu highlight |
| `primaryLight` | `#51A0B0` | Softer variant |
| `descriptionLink` | `#2A6B7C` | Darker primary: connected (description-linked) text and its thin underline |
| `primaryBright` | `#58C4D8` | Fills on active controls and toggles |
| `aiCyan` | `#00D4FF` | AI, and only AI — the one place the app is allowed to glow |
| `destructive` | `#B45309` | Delete and discard. Amber-brown, never red |
| `glassTint` | `#DDF6F2` | Frost behind glass surfaces |
| `menuTint` | `#F4F4F5` | Frost behind context menus |

**There is no success green and no error red.** A personal workspace has nothing to alarm the user about; failures are reported in words, in `Theme.colorScheme.error`, not in colour blocks.

### Opacity as the main tool

Most variation comes from alpha over the tokens above, not from more tokens. The conventions:

| Range | Meaning |
|-------|---------|
| 0.88–0.94 | Primary text on a surface |
| 0.68–0.82 | Secondary text, resting icons |
| 0.38–0.55 | Disabled |
| 0.08–0.22 | Hover and pressed fills |
| ~0.18 | Modal scrim (`OverlayDialogStyle.barrierColor`) |

### Topic colour on files

A topic carries any `#RRGGBB` colour (picked in [`color_dialog.dart`](color_dialog.dart); 16 presets remain as shortcuts in [`../ux/topic/topic_appearance.dart`](../ux/topic/topic_appearance.dart), default `#6B7280`), and its **files wear it**. This is the app's main wayfinding cue: you know which topic you are in from the colour of the paper, before reading a word.

| Rule | Why |
|------|-----|
| The canvas stays neutral | A tinted window would fight the panes and tire the eye |
| The main topic's panes stay pure white | Home is the neutral place |
| The fill is a gentle wash, `minFileTint` 4.5% to `maxFileTint` 17% | Enough to read as coloured paper, never enough to compete with text |
| The border is the same colour, saturated, at `filePaneBorderWidth` 0.5px | A hairline is what makes the tint look intentional |
| **Each file's strength is fixed to its id** | See below |

`AppColors.fileTintStrength(fileId)` spreads files across that range using a multiplicative hash of the file id. The strength is arbitrary — panes in a topic are pleasantly varied rather than uniform — but it is **stable**: a file keeps its exact shade when the topic is rearranged, when the app restarts, and on another device. Nothing about a file's position or content may ever feed into this, or reordering would repaint the topic.

(v1 varied the tint by *file type* — `plan` heaviest, `text` lightest. The document model has no file types, so identity took over the same range.)

## Text

All of it comes from [`app_typography.dart`](app_typography.dart). One family, few weights, one colour.

| Style | Size | Height | Weight | For |
|-------|------|--------|--------|-----|
| `pageTitleStyle` | 19 | 1.3 | w500 | Topic title |
| `noteTitleStyle` | 14 | 1.3 | w500 | Dialog titles. File names in the pane use this plus **w700** |
| `blockHeaderStyle` | 14 | 1.4 | w600 | Headers inside a document |
| `noteBodyStyle` | 12.5 | 1.55 | w400 | Document body, inputs |
| `listItemStyle` | 12.5 | 1.38 | w400 | Bullets |
| `taskRowStyle` | 12.5 | 1.38 | w400 | Task rows |
| `metaStyle` | 12 | 1.4 | w400 | Meta, hints (in `textHint`) |
| `sidebarSectionStyle` | 13 | 1.35 | w400 | Sidebar sections |
| `sidebarItemStyle` | 11 | 1.4 | w400 | Sidebar topics |

Weights are only **w400 / w500 / w600**. Bold is something the user applies to their own text, not something the interface does to itself.

**Font by language, not by content:** English gets Inter (`google_fonts`); Hebrew gets **SF Hebrew** with system fallbacks (`.SF Hebrew`, `Arial Hebrew`, `Noto Sans Hebrew`), and letter spacing forced to 0 because negative tracking mangles Hebrew. `AppTypography.configure` is called when the language changes. Document styles must be **read per build**, never cached as `static final`, or a language switch leaves Inter under Hebrew text.

Chrome under 12px exists, but only for labels that must not be read as content: context menu rows at 11.5, popup menus and sidebar items at 11, the `AI` badge at 9.

### Two kinds of text

The distinction matters and is easy to get wrong:

| Text | Style source |
|------|--------------|
| **App chrome** — menu labels, dialog titles, buttons, sidebar | `AppTypography` chrome styles |
| **File content** — what a user types in a document | `noteBodyStyle`, `listItemStyle`, `taskRowStyle` |

Changing the document default size or font is a UI change, but it changes how every file reads — a deliberate decision, not a tweak.

## Spacing and shape

[`AppSpacing`](app_colors.dart) is the scale: `xs 4`, `sm 6`, `md 12`, `lg 18`, `xl 26`, plus `blockGap 3` between blocks inside a document and `notePadding` / `canvasPadding` at 12.

| Metric | Value | Where |
|--------|-------|-------|
| Gap between file panes | 8 | `AppLayoutSpacing.gap` |
| Bottom bar height | 44 desktop / 38 phone | `AppBottomBarMetrics` |
| Topic header height | 32 | `AppTopicHeaderMetrics` |
| Sidebar width | 200 default, 150–340 desktop; phone drawer ~62% width, max 248, full height | `AppSidebarMetrics` |
| Context menu row height | 28 | `AppContextMenu` |

**Radii**, smallest to largest: `4` marks and chips · `6` menu rows · `8` inner blocks · `10` cards and file panes · `12` menu bubbles · `14` sidebar · `16` floating chrome · `22` dialogs · `999` pills.

**Border widths** are all sub-pixel-ish on purpose: `0.5` file panes, `0.65` menus, `0.8`–`0.9` cards and fields, `1`+ only for a focus ring.

**Motion** is short and never bouncy: `140ms` for a toggle or mark, `200ms` for a pane or menu change, `220ms` for a carousel snap. `Curves.easeOut` in, `easeIn` out.

## Glass

Glass is the app's signature surface: a blurred, translucent panel for anything that floats over content. It is defined once in [`glass_surface.dart`](glass_surface.dart), and **nothing rolls its own blur**.

| Preset | Blur | Tint | For |
|--------|------|------|-----|
| `dialog` | 24 | `glassTint` 0.78, elevation 7 | Modals via `AppGlassDialog` |
| `floating` | 24 | `glassTint` 0.78, elevation 4 | Floating pills, layout tiles |
| `dragMode` | 14 | `glassTint` 0.38, hairline white border | Document Move / task Reorder mode frames ([`../files/editor/drag_mode_frame.dart`](../files/editor/drag_mode_frame.dart)) |
| `opaqueChrome` | 0 | Solid white + lift shadow | Bottom bar segments, view chrome menu, `+` buttons |
| `aiAccent` | 0 | Solid, `aiCyan` border | The AI segment, with `AI` on the outline |

Solid chrome is not a contradiction: the bottom bar sits over scrolling text all day, and blur there would shimmer.

## Controls

Small, quiet, and generous to click. Every control's hit target is larger than its paint.

| Control | Shape |
|---------|-------|
| Text / filled / outlined buttons | Pill (`radius 999`), padding 16×8, min height 34, `primaryBright` fill at 14% resting → 18% hover → 22% pressed |
| `AppSegmentedToggle` | Chips 10×5, gap 6, radius 6, selected fill `primaryBright` 0.92 |
| `AppSwitch` | Material switch at **0.78 scale** — full size looks like a control panel |
| `TaskMark` | Custom 14px mark, radius 4, 140ms, in `aiCyan` when done, 32×32 hit target |
| `GlassCircleButton` | 34px circle, 16px icon |
| Bottom bar icons | 22px icon, 34×34 minimum target |

Marking and selection are **gentle by rule**: a translucent fill or a hairline ring, never a hard colour block or a heavy outline.

## Dialogs and menus

**Hug the content.** Dialogs and choice bubbles are sized and padded for what they hold — not for empty air. Default max width is `AppDialogMetrics.maxWidth` (280); only pickers/lists that need room use `wideWidth` (400), the automation builder uses `extraWideWidth` (460) so a calendar and clock can sit side by side, and the fill-file snippet editor uses `fileEditorWidth` (520) because it hosts a real file pane. Chrome padding is 12/10/12/8; field gaps are 8. Do not pass a custom `width:` on a dialog unless the body truly overflows at 280. Metrics live in [`dialog_metrics.dart`](dialog_metrics.dart).

The preferences dialog is the **reference** glass dialog. Every other dialog uses the same shell and the same field language.

| Kind | Widget | Shape |
|------|--------|-------|
| Standard dialog | `AppAdaptiveDialogShell` → `AppGlassDialog` | Max width 280, radius 16, padding 12/10/12/8, tight hairline dividers |
| Phone dialog | `AppAdaptiveDialogShell` | Radius 16, inset 14×16, tint 0.94, matching tight padding |
| Wide dialog | same shell + `wideWidth` | 400 — colour/emoji pickers, shortcut list, automations list |
| Extra-wide dialog | same shell + `extraWideWidth` | 460 — automation builder (calendar + clock) |
| File-editor dialog | `AppGlassDialog` + `fileEditorWidth` | 520 — fill-file snippet (hosts `DocumentPane`) |
| Confirm | `showAppConfirmDialog` | Same shell; destructive answers use amber-brown text |
| Full-screen overlay | `OverlayDialogShell` + `OverlayDialogStyle` | Scrim black 18%, cards radius 14 |
| Context menu (right-click **and** file `⋯`) | `../ux/widgets/app_context_menu.dart` | Bubble radius 12, rows 28 high, 11.5px labels, `menuTint` frost, highlight in `primary`; compact width 128 + downward caret for anchored create menus |
| Hover bubble | `../ux/widgets/details_hover_bubble.dart` | Radius 10, blur 18, white 82%, max 320×240 |
| Native popup menu | Avoid — use `AppContextMenu` | — |

Route every dialog through [`adaptive_dialog.dart`](adaptive_dialog.dart). List pickers are keyboard-walked (↑/↓, Enter, Escape) by UX [`dialog_choice_list.dart`](../ux/dialogs/dialog_choice_list.dart). Form fields autofocus and submit on Enter; picker rows are in the tab order; confirmations accept Enter for the confirm answer. Fields inside dialogs use the helpers in [`dialog_field_style.dart`](dialog_field_style.dart):

| Helper | Rule |
|--------|------|
| `AppDialogField` | The field's **name sits above it** in 11px meta text — never as a hint inside the field |
| `AppDialogChoiceField` | Multiple choices as chips; the chosen one is filled in **bright teal** (`primaryBright`) |
| `AppDialogPickerField` | Opens a **secondary** dialog for the value (colour, emoji) — a dialog never grows a picker inside itself, except the automation builder's When section. Tab-focusable; Enter/Space opens it. Multi-pane pickers draw `paneFocusDecoration` on the active pane and a `DialogKeyboardHint` under the body |
| Colour | [`color_dialog.dart`](color_dialog.dart) → `showAppColorDialog` | Full HSV spectrum + hex field; optional preset swatches. Tab walks presets → spectrum → hex; arrows move inside the focused pane (presets, HSV, or hex); Enter chooses. Presets and spectrum stay LTR in Hebrew — not language. Used for topic theme, text colour, graph colour |
| Time | [`time_picker_dialog.dart`](time_picker_dialog.dart) → `AppCompactTimePicker` | Same card size as the calendar. 24-hour numbered dial above, typed hour and minute below (no AM/PM, no dropdowns). Hour then minute stays **LTR** even in Hebrew — it is numeric clock notation. `showAppTimePicker` remains for a secondary dial if something else needs one. |
| Calendar | [`compact_calendar.dart`](compact_calendar.dart) → `AppCompactCalendar` | Compact month grid. Presentational: marked days and labels come from the caller. |

A **secondary** dialog — one opened from a dialog — keeps the same shell and gains no chrome. Depth is expressed by the scrim stacking, not by shadows getting heavier. Topic colour and emoji are picked this way from the create/edit topic dialog.

The `⋯` on a file opens `AppContextMenu` at the button — the same bubble as a right-click, not a Material `PopupMenuButton`.

## Icons

[Lucide](https://lucide.dev) at the **200 stroke weight**, named in [`app_icons.dart`](app_icons.dart) and drawn through `AppIcon` (20px default, `text` at 82%, `textHint` at 38% when disabled). The thin stroke is what keeps icons as quiet as the type next to them — including the `⋯` on a file (`AppIcons.more`), which must never be a Material `Icons.more_vert`.

Sizes in use: 14 dividers and marks · 16 circle buttons and file menus · 18 sidebar and inline actions · 20 default · 22 bottom bar.

A **saved AI action** picks its icon from the vocabulary in [`action_icons.dart`](action_icons.dart) — including emoji and image, same stroke weight, keyed by name so the database stores `'checklist'` and never a code point. [`action_icon_picker.dart`](action_icon_picker.dart) shows them as a grid in a secondary dialog, and falls back to sparkles for a key it no longer knows.

`GlassCircleButton` and every other chrome control draw through `AppIcon`, never a bare `Icon(...)` with a Material glyph.

## Bilingual

Every surface must work in English (LTR) and Hebrew (RTL). Use [`bilingual_layout.dart`](bilingual_layout.dart) primitives (`StartTrailingRow`, `DialogActionsRow`) rather than hardcoding a direction. Rules: [`../../core/l10n/BILINGUAL.md`](../../core/l10n/BILINGUAL.md).

## File map

| Concern | Files |
|---------|-------|
| Colours, spacing scale | [`app_colors.dart`](app_colors.dart) |
| Chart / multi-series palettes | [`app_color_palettes.dart`](app_color_palettes.dart) — 8 colours per set (`seriesLimit`) |
| Material theme | [`app_theme.dart`](app_theme.dart) |
| Text | [`app_typography.dart`](app_typography.dart) |
| Glass | [`glass_surface.dart`](glass_surface.dart) |
| Controls | [`app_segmented_toggle.dart`](app_segmented_toggle.dart), [`app_switch.dart`](app_switch.dart) |
| Dialogs | [`adaptive_dialog.dart`](adaptive_dialog.dart), [`dialog_metrics.dart`](dialog_metrics.dart), [`color_dialog.dart`](color_dialog.dart), [`time_picker_dialog.dart`](time_picker_dialog.dart), [`compact_calendar.dart`](compact_calendar.dart), [`overlay_dialog_shell.dart`](overlay_dialog_shell.dart), [`overlay_dialog_style.dart`](overlay_dialog_style.dart), [`dialog_field_style.dart`](dialog_field_style.dart) |
| Icons | [`app_icons.dart`](app_icons.dart), [`action_icons.dart`](action_icons.dart), [`action_icon_picker.dart`](action_icon_picker.dart) |
| Cards and previews | [`note_widgets.dart`](note_widgets.dart), [`overlay_file_preview_card.dart`](overlay_file_preview_card.dart), [`layout_preview_icon.dart`](layout_preview_icon.dart), [`object_look_preview.dart`](object_look_preview.dart) |
| Carousel | [`horizontal_carousel.dart`](horizontal_carousel.dart) |
| RTL primitives | [`bilingual_layout.dart`](bilingual_layout.dart) |

## Rules

- **No hardcoded visual values outside this folder.** Colours, font sizes, radii, blur amounts, and spacing constants live here. A one-off `Color(0x…)` in a widget is a bug in this area, not a shortcut.
- UI widgets are **presentational**: they take values and callbacks, never call services or `AppState`.
- Nothing here decides *when* it is shown — that is [UX](../ux/AREA.md).
- Reach for opacity over a new token. Reach for an existing radius over a new one.
- Changing a shared style means checking both app chrome and file content, since both consume this area.
- Anything floating uses a `AppGlassStyle` preset. Do not invent blur and tint values.
- Keep it small and quiet. If a change makes something louder than the user's own text, it is wrong.

## Where the style is still not honest

Tracked as **U1–U5** in [`BACKLOG.md`](../../../../BACKLOG.md): the context menu and hover bubble keep some local blur values instead of an `AppGlassStyle` preset, the legacy AI diff dialog and its shell bypass `AppGlassDialog` and `AppTypography`, document heading sizes still derive from a formula (now named as `documentHeadingStyle`), and some Material icons remain among the Lucide ones in older surfaces.
