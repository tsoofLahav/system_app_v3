# RTL solution

How the file editor stays fluent in Hebrew (and other RTL), including mixed Hebrew + English/numbers.

This folder is the **only** place that owns RTL/BiDi policy for editable text. Wire it through [`../formatted_text_field.dart`](../formatted_text_field.dart). Do not add competing caret math in `DocumentTextFlow` or embed widgets.

## Boundary

| Layer | Owns |
|-------|------|
| [`DocumentTextFlow`](../../editor/document_text_flow.dart) | Segment order, moving **between** parts, click in empty space **under the file** → logical end of last part |
| This folder + Flutter `TextField` | Base direction, visual arrows, caret/selection/IME **inside** a part |

Custom code decides “leave paragraph A for task B”. Flutter decides “where on these glyphs is the caret?” — except empty padding (below), which Flutter gets wrong in BiDi. **Flutter also paints the caret.** Do not hide `showCursor` or overlay a bar.

## The three pieces

```
rtl/
  RTL.md                      ← this file
  rtl.dart                    ← public barrel + small helpers
  paragraph_text_direction.dart
  rtl_caret_motion.dart       ← FormattedTextField visual ←/→
  empty_space_caret.dart
  embed_caret_hit.dart        ← tap affinity + BiDi-gap snap; run-aware arrows
  super_editor_text_direction.dart  ← SE empty → ambient direction
  super_editor_visual_caret.dart    ← SE visual ←/→ + selectors
```

### 1. Base direction — `paragraph_text_direction.dart`

Each field gets an explicit `TextField.textDirection`:

1. First **strong** directional character in the text (Unicode P2/P3 style) → RTL or LTR  
2. Else ambient UI `Directionality` (empty / digits-only paragraphs)

Example: `אני משתמש ב-Flutter 3.29 היום` → RTL base, so Flutter lays out the Latin/number runs inside an RTL paragraph.

**Do not** reverse the string. Direction only.

Helper: `resolveFieldTextDirection(text, ambient)` in `rtl.dart`.

### 2. Visual arrow keys — `rtl_caret_motion.dart`

Flutter moves the caret through the **string**. In RTL that makes ← walk the wrong way on screen.

**Fix:** wrap the field in `Actions` that flip horizontal motion intents (`forward: !forward`) and hand them back to the field’s own action. Flutter still performs the move (key repeat, graphemes, shift-extend stay intact).

**Do not** reimplement arrows in a `onKeyEvent` handler.

`wrapVisualCaretMotion` always wraps the field in `Actions` (same tree shape so an IME language switch does not remount the `TextField`). Flip actions apply only when the **glyph run at the caret** is RTL. European numbers and Latin inside a Hebrew paragraph paint LTR — do not flip those, or the caret walks the wrong way on the number (Super Editor already does this).

**Not flipped:** Cmd+arrow / Home / End (they share intents; flipping would break Home/End). Documented as a known gap in the files [`AREA.md`](../../AREA.md).

Cross-part exits (arrow off the edge of a bullet into the next segment) stay in `FormattedTextField` / `DocumentTextFlow`; the exit **edge** is mirrored when the field is RTL (left arrow leaves from the logical end).

### 3. Empty-padding taps — `empty_space_caret.dart`

Full-width fields leave empty space beside glyphs (especially RTL). Flutter’s `getPositionForPoint` often lands on a BiDi boundary (start of line, or after an English/number run).

| Tap target | Who places the caret |
|------------|----------------------|
| On painted glyphs (few px slop), or empty `boxes` | Flutter hit-test, then **affinity** so an end-of-line tap does not jump to the line below |
| Gap between BiDi runs on the same line (Hebrew vs number/English) | Snap to the nearest glyph, then affinity |
| Empty padding **beside** the line slot | Logical line end via `getLineAtOffset` (probe glyph **center** only to learn which line) |
| Extra cell/row padding above/below ink (tall cells, centered tasks) | Flutter — do not treat ink-bottom as the line |
| Empty space under the whole file (outside every field) | `DocumentTextFlow` → logical end of last part |

Correction runs in `FormattedTextField.onTap` **in the same event turn** (before paint). Never post-frame — that flashes wrong → right. Apply it on a **collapsed click** only. A drag, an existing mark, or Shift+click keeps Flutter’s selection — padding→line-end on mouse-up is the Hebrew “whole line immediately” bug.

## Wiring checklist (`FormattedTextField`)

- [ ] `textDirection: resolveFieldTextDirection(text, ambient)`
- [ ] `textAlign: TextAlign.start` (follows direction)
- [ ] `wrapVisualCaretMotion(...)` always (identity actions when LTR)
- [ ] Primary pointer down stores global position; `onTap` calls `embedCaretForTap` **only on a collapsed click** (not drag / mark / Shift+click)
- [ ] Cross-part arrow edge uses the **resolved** field direction, not only ambient locale
- [ ] Horizontal arrows flip only on an RTL glyph run (not on numbers / Latin)

## Super Editor (file body)

The file body is Super Editor, not `FormattedTextField`. Same direction rules apply:

| Rule | How |
|------|-----|
| Base direction | [`ambientAwareTextBuilders`](super_editor_text_direction.dart) — first strong char, else ambient UI (empty Hebrew paragraphs start RTL so the caret sits on the right). Do **not** use stock `getParagraphDirection` alone (it hard-codes empty → LTR). |
| Align | Stylesheet sets `TextAlign.start` (not absolute left/right) |
| Visual ←/→ | [`SuperEditorVisualCaretPlugin`](super_editor_visual_caret.dart) + `withVisualHorizontalSelectors` — same flip idea as `rtl_caret_motion.dart` (character/word; not Cmd+line / Home / End) |
| Selection wash | SE’s beneath-layer highlight is unreliable for RTL/Hebrew → [`selection_background_phase.dart`](../../editor/selection_background_phase.dart) also paints `BackgroundColorAttribution` on the selected span |

Embed fields (table cells, info, …) still use `FormattedTextField` + the three pieces above.

## What we deliberately do not do

- Reverse Hebrew strings or map “visual columns” ourselves for normal typing  
- Fight the `TextField` from the parent editor on taps **inside** a field box (causes caret jump)  
- Post-frame caret “snaps”  
- Hide `showCursor` / overlay-paint a caret / write `selection` on every keystroke  
- Rely on SE’s translucent beneath-layer selection alone for Hebrew

## Regression tests

```bash
flutter test \
  test/rtl_paragraph_text_direction_test.dart \
  test/rtl_empty_space_caret_test.dart \
  test/rtl_super_editor_direction_test.dart \
  test/document_text_flow_test.dart \
  test/files/table_grid_nav_test.dart \
  test/files/table_cell_session_test.dart \
  test/ux/object_arrow_pad_test.dart
```

Manual (Hebrew UI):

1. Empty file paragraph — caret already on the **right** (no left→right jump on first Hebrew key)  
2. Type `אני משתמש ב-Flutter 3.29 היום` — layout stays coherent; caret at end after typing  
3. ← → move the caret the way the keys point on screen (file body **and** object fields)  
4. Click empty space beside the line → caret at logical end (resume writing)  
5. Click below the paragraph / empty file → caret at end of last line  
6. Click on a Hebrew letter mid-word → caret stays where Flutter put it on the glyph  
7. Click mid-word in a table cell / task / info (including tall-cell padding below ink) → caret stays on the word, not the line end  
8. Click the end of a wrapped line in an object field → caret stays on that line (not the start of the next)  
9. Numbers inside Hebrew in an object field — arrows and clicks follow the number run, like the file body

## Related

| Topic | Where |
|-------|--------|
| Continuous document / segments | [`../../AREA.md`](../../AREA.md) |
| Spans / mark / menus | [`../RICH_TEXT.md`](../RICH_TEXT.md) |
| Graph/table reading direction | Embed widgets use ambient `Directionality` for column mirroring — separate from this text-caret solution |
| Table grid ←/→ | [`../table_grid_nav.dart`](../table_grid_nav.dart) — physical pad/hardware arrows → visual cell. Grid RTL = app `Directionality` (col 0 on the right in Hebrew). Landing uses the destination cell’s first-strong direction so visual-right is logical start in RTL. Phone object-pad icons never mirror (UX chrome). |
