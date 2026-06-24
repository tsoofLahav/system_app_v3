# Rich text in blocks

Inline formatting (bold, italic, underline, size) for text/header/summary blocks.

## Rules (do not break these)

### 1. One source of truth while editing

When a `SpanTextEditingController` field **has focus** (or a context menu is open for it), the **controller** owns `text` + `spans`. The parent `Block.content` is **write-only** until focus is lost.

- **Never** call `loadFromContent`, `setRichState`, or span-only sync while focused.
- Use `syncRichControllerFromBlockIfIdle()` from `rich_text_block_sync.dart` in `didUpdateWidget`.
- Sync must **also skip** when `BlockTextFocusRegistry.activeController == controller` — after the context menu closes, focus is often still lost for a frame while the field remains the active editor. Syncing then overwrote spans and caused formatting to “drag” onto new typing.

### 2. Format target is frozen at menu open

Format applies to:

- **Marked text** — non-collapsed selection, or
- **Current paragraph** — from previous `\n` (or start) to next `\n` (or end) when the caret is collapsed.

`FormatRange.resolve()` in `format_range.dart` implements this. It runs **once** when the menu opens (`BlockTextFocusRegistry.openMenuSession`). The range is stored as `_frozenRange` and used for cut/copy/paste/format — not re-read from a selection that may have been cleared by focus loss.

`FormatRange.capturePending()` on secondary pointer-down in `FormattedTextField` helps preserve the selection before focus blurs. **Only the first valid pending capture is kept** until the menu consumes it — do not capture again from `file_section` or other parents after focus loss (that replaced a word selection with the whole paragraph).

### 3. Span shifts only on text changes

`SpanTextEditingController` updates spans in `handleTextChange()` only when `text != _previousText`. Selection changes must **not** trigger span math.

After formatting, `_previousText` must match `text` (see `applyFormatAction`).

### 4. Inserted text is unstyled unless strictly inside a span

`remapSpansForTextEdit` (not geometric offset shifting) assigns styles per character. A new character at index `i` inherits a span only when `span.start <= i < span.end` in the **pre-insert** document. Typing at `index == span.end` (immediately after a bold word) stays unstyled.

### 5. No compose / “future typing” mode

Formatting always affects an existing character range. Newly typed characters are unstyled unless the caret is **inside** a styled span.

### 6. Keep menu integration minimal

`BlockTextFocusRegistry` only:

- tracks the active field,
- freezes `FormatRange` for the menu session,
- runs clipboard/format actions.

**Allowed:** a paint-only selection overlay in `FormattedTextField` while the block menu is open:

- Reads `frozenFormatRange` only (read-only).
- `_FrozenSelectionOverlay` finds the inner `RenderEditable` in the `TextField` render tree and calls `getBoxesForSelection` on it, then transforms rects into the `CustomPaint` host space. **Do not** recompute boxes with a separate `TextPainter` — that misaligns in RTL and horizontally vs the real field.
- `FrozenSelectionPainter` only fills precomputed rects.
- `menuSessionListenable` triggers remeasure/repaint when the menu opens/closes — it must not drive business logic.

**Forbidden during the menu:** re-requesting focus, rewriting `controller.selection`, or any registry writes that change spans/text. Those caused span/state corruption.

### 7. Per-property format actions

Each menu action (`text:bold`, `text:italic`, `text:underline`, `text:size_up`, `text:size_down`) mutates **one** style attribute per character in the format range via `applyActionToMark` inside `applyFormatActionToRange`. Never merge the selection with `styleForRange` and apply one style over the whole range — that leaks bold onto regular text when only size changes.

Toggle semantics: bold/italic/underline flip independently per character in the range.

## Regression checklist

Before merging any rich-text PR:

1. Run `flutter test test/span_shift_test.dart`
2. Manual: bold a word → click after it → type (new text stays regular)
3. Manual: mixed bold + regular lines → size up (bold stays bold, regular stays regular)
4. Manual: select text → right-click → selection highlight visible during menu and matches selected glyphs (English + Hebrew / RTL)
5. Confirm no edits to `remapSpansForTextEdit` boundary rule (`start <= index < end`) without new tests
6. Confirm no `setRichState` / `loadFromContent` while `hasFocus || activeController == controller`
7. Confirm selection overlay still uses `RenderEditable.getBoxesForSelection` (not a duplicate `TextPainter`)

## File map

| File | Role |
|------|------|
| `format_range.dart` | What to format (selection or paragraph) |
| `text_formatting.dart` | Pure span math + `TextSpan` rendering |
| `span_text_editing_controller.dart` | `TextEditingController` + spans + `handleTextChange` |
| `block_text_focus.dart` | Active field + frozen menu range + menu actions |
| `formatted_text_field.dart` | `TextField` wrapper, focus registration, `_FrozenSelectionOverlay` |
| `frozen_selection_painter.dart` | Paints precomputed selection rects during menu |
| `rich_text_block_sync.dart` | Idle-only sync from block → controller |
| `block_context_menu.dart` | Opens/closes menu session around `showMenu` |

## Persistence

Block content fields:

- `text` — plain string
- `spans` — `[{start, end, bold?, italic?, underline?, size?}]` (half-open ranges)
- `compose_style`, `parchment`, `text_style` — legacy; cleared on save

## Tests

Run `flutter test test/span_shift_test.dart` after any change to span shifting, format application, or selection overlay.
