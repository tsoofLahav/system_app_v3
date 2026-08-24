# Rich text in blocks

Inline formatting (bold, italic, underline, size) for text/header/summary blocks.

## Rules (do not break these)

### 1. One source of truth while editing

When a `SpanTextEditingController` field **has focus** (or a context menu is open for it), the **controller** owns `text` + `spans`. The parent `Block.content` is **write-only** until focus is lost.

- **Never** call `loadFromContent`, `setRichState`, or span-only sync while focused.
- Use `syncRichControllerFromBlockIfIdle()` from `rich_text_block_sync.dart` in `didUpdateWidget`.
- Sync must **also skip** when `BlockTextFocusRegistry.activeController == controller` — after the context menu closes, focus is often still lost for a frame while the field remains the active editor. Syncing then overwrote spans and caused formatting to “drag” onto new typing.

### 2. One marking, resolved once and frozen at menu open

Every action targets **the mark**, resolved by a single rule:

1. **Anything marked** → that is the target, across as many parts as it covers.
2. **Nothing marked** → the **line at the caret** (previous `\n` or start, to next `\n` or end).

`DocumentMark.resolve()` in [`../editor/document_mark.dart`](../editor/document_mark.dart) is the only implementation of this rule, and cut/copy/paste/format/AI all go through it via `BlockTextFocusRegistry.resolveMark()`.

**Never read a single field's `controller.selection` to decide what an action affects.** A field's selection only describes how that field paints itself. Inside the file editor a marking routinely spans several fields, and reading one of them would silently act on a fraction of what the user marked.

The mark is captured on secondary pointer-down (`capturePendingMark`) and frozen for the menu session (`openMenuSession`), so focus loss or a collapsed selection cannot change the target mid-menu. `FormatRange` remains only as the fallback for a lone field outside any document flow.

**Embed objects:** right-click on text always registers that field first, then freezes selection → else the last non-collapsed snapshot → else the line at the caret. Right-click on object chrome (not text) freezes the **whole field** via `prepareObjectMenuMark`. Embed fields keep `DocumentSecondaryTap` until the menu closes so Super Editor cannot open a second menu that clobbers the freeze.

**Only the first valid pending capture is kept** until the menu consumes it — do not capture again from parents after focus loss (that replaced a word selection with the whole paragraph). Nested `openMenuSession` must not re-resolve from a live collapsed selection.

### 3. Span shifts only on text changes

`SpanTextEditingController` updates spans in `handleTextChange()` only when `text != _previousText`. Selection changes must **not** trigger span math.

After formatting, `_previousText` must match `text` (see `applyFormatAction`).

### 4. Inserted text is unstyled unless strictly inside a span

`remapSpansForTextEdit` (not geometric offset shifting) assigns styles per character. A new character at index `i` inherits a span only when `span.start <= i < span.end` in the **pre-insert** document. Typing at `index == span.end` (immediately after a bold word) stays unstyled.

### 5. No compose / “future typing” mode

Formatting always affects an existing character range. Newly typed characters are unstyled unless the caret is **inside** a styled span.

### 6. Keep menu integration minimal

`BlockTextFocusRegistry` only:

- tracks the active field and the flow it belongs to,
- freezes the `DocumentMark` for the menu session,
- runs clipboard/format actions against that mark.

**Allowed:** a paint-only selection overlay in `FormattedTextField` while the block menu is open:

- Reads `frozenMark` only when a document mark is frozen (read-only). `frozenFormatRange` is paint fallback only for a lone field with no mark. Never paint both.
- While the overlay is showing the mark, `TextField.selectionColor` is transparent so native selection and the mark never stack as two washes.
- `_FrozenSelectionOverlay` finds the inner `RenderEditable` in the `TextField` render tree and calls `getBoxesForSelection` on it, then transforms rects into the `CustomPaint` host space. **Do not** recompute boxes with a separate `TextPainter` — that misaligns in RTL and horizontally vs the real field.
- `FrozenSelectionPainter` only fills precomputed rects.
- `menuSessionListenable` triggers remeasure/repaint when the menu opens/closes — it must not drive business logic.

**Forbidden during the menu:** re-requesting focus, rewriting `controller.selection`, or any registry writes that change spans/text. Those caused span/state corruption.

### 7. Per-property format actions

Each menu action (`text:bold`, `text:italic`, `text:underline`, `text:size_up`, `text:size_down`, `text:color:…`) mutates **one** style attribute per character in the format range via `applyActionToMark` inside `applyFormatActionToRange`. Never merge the selection with `styleForRange` and apply one style over the whole range — that leaks bold onto regular text when only size changes.

Text colour: the context menu offers **Choose color** → `showAppColorDialog` (menu session stays open so the mark stays frozen) → `text:color:#RRGGBB`, plus **Clear color**. No hardcoded red/blue/green menu rows.

Toggle semantics: bold/italic/underline flip independently per character in the range.

Description-link colour (`AppColors.descriptionLink`) is paint-only: `SpanTextEditingController.setDescriptionPaintRanges` / `displaySpans`. Never write it into persisted `spans`.

## Regression checklist

Before merging any rich-text PR:

1. Run `flutter test test/span_shift_test.dart test/document_mark_test.dart test/continuous_text_test.dart test/rtl_paragraph_text_direction_test.dart test/rtl_empty_space_caret_test.dart`
2. Manual: bold a word → click after it → type (new text stays regular)
3. Manual: mixed bold + regular lines → size up (bold stays bold, regular stays regular)
4. Manual: select text → right-click → **one** highlight during menu, matching the selection (not selection + whole line)
5. Manual: mark from a paragraph through a bullet into a cell → right-click → the highlight covers all three, and the action affects all three
6. Manual: nothing marked → right-click mid-line → **one** whole-line highlight; action affects that line only
5. Confirm no edits to `remapSpansForTextEdit` boundary rule (`start <= index < end`) without new tests
6. Confirm no `setRichState` / `loadFromContent` while `hasFocus || activeController == controller`
7. Confirm selection overlay still uses `RenderEditable.getBoxesForSelection` (not a duplicate `TextPainter`)

## File map

| File | Role |
|------|------|
| `../editor/document_mark.dart` | **The mark** — the one target every action resolves |
| `../editor/document_text_flow.dart` | Document-wide caret/selection across parts |
| `format_range.dart` | Range fallback for a lone field with no document flow |
| `text_formatting.dart` | Pure span math + `TextSpan` rendering |
| `span_text_editing_controller.dart` | `TextEditingController` + spans + `handleTextChange` |
| `block_text_focus.dart` | Active field + frozen menu range + menu actions |
| `formatted_text_field.dart` | `TextField` wrapper, focus registration, `_FrozenSelectionOverlay`; wires the [RTL solution](rtl/RTL.md) |
| [`rtl/`](rtl/RTL.md) | **RTL solution** — base direction, visual arrows, empty-padding caret (see `RTL.md`) |
| `document_context_menu.dart` | Text, list, and table-cell menu entries |
| `frozen_selection_painter.dart` | Paints precomputed selection rects during menu |
| `rich_text_block_sync.dart` | Idle-only sync from block → controller |
| `block_context_menu.dart` | Opens/closes menu session around `AppContextMenu` bubble |

## Persistence

Block content fields:

- `text` — plain string
- `spans` — `[{start, end, bold?, italic?, underline?, size?}]` (half-open ranges)
- `compose_style`, `parchment`, `text_style` — legacy; cleared on save

## Tests

Run `flutter test test/span_shift_test.dart` after any change to span shifting, format application, or selection overlay.
