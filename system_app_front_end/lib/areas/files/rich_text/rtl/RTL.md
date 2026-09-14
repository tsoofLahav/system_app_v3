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
  super_editor_bidi_caret.dart ← SE single-tap padding only; other hits native
  super_editor_text_direction.dart  ← SE empty → ambient direction
  super_editor_visual_caret.dart    ← SE visual ←/→ + selectors
  ios_visual_handles.dart           ← iOS handles: upstream/downstream + tight wash
```

### 1. Base direction — `paragraph_text_direction.dart`

Each field gets an explicit `TextField.textDirection`:

The persisted **Writing direction** preference has two modes:

1. **First letter** (default): first strong character → RTL or LTR; otherwise ambient UI direction.
2. **App language**: always ambient UI direction.

`WritingDirection` owns this policy for both engines. Object text fields use one
base direction for the whole field; SE resolves each text node. Changes only
update layout after keyboard idle; they never insert spaces or direction marks.
Explicit RTL/LTR from the text menu takes precedence over this preference.
Use default direction removes the override. SE stores `writingDirection` on
text-node metadata, encoded as a visible storage prefix (never editable text;
see [DOCUMENT_TEXT.md](../../editor/DOCUMENT_TEXT.md)). An action affects touched
paragraphs/list items, excludes a final selection endpoint at offset zero, and
is undoable. Rich object fields store `direction` in existing span metadata and
apply it to the whole field, including future replacement text and empty fields.
Plain image captions follow the default policy, with no explicit override menu.
No timer inserts spaces; no hidden direction characters are added.

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
| On painted glyphs (0.5px horizontal tolerance, 4px vertical leading tolerance), or empty `boxes` | Flutter hit-test, then **affinity** so an end-of-line tap does not jump to the line below |
| Gap between BiDi runs on the same line (Hebrew vs number/English) | Snap to the nearest glyph, then affinity |
| Empty padding **beside** the line slot | Object fields: logical line end via `getLineAtOffset`; SE: greatest logical grapheme end on the aimed rendered line (its stock helper probes physical right) |
| Extra cell/row padding above/below ink (tall cells, centered tasks) | Flutter — do not treat ink-bottom as the line |
| Empty space under the whole file (outside every field) | `DocumentTextFlow` → logical end of last part |

Correction runs in `FormattedTextField.onTap` **in the same event turn** (before paint). Never post-frame — that flashes wrong → right. Apply padding→line-end on a **collapsed single click** only. A drag or Shift+click uses the nearer visual edge / nearest glyph run (`bidiAwareOffsetForEditable`) so a number in Hebrew does not steal the mark — not padding→line-end (that is the Hebrew “whole line immediately” bug). Double/triple tap keep Flutter so they can stay a word / sentence.

Desktop Flutter paints selection with `BoxWidthStyle.max` (full paragraph width per line). In RTL the glyphs sit on the right, so that extra box is the trail to the left edge — even when the mark is only a word. Super Editor paints span-tight wash; object fields set `selectionWidthStyle: BoxWidthStyle.tight` so they match. Leave `selectionHeightStyle` at Flutter’s default — `tight` hugs the ink and sits off Hebrew lines that have extra leading. Color-emoji fallbacks need `AppTypography.fieldStrut` or they steal line metrics and the wash is right on emoji lines and wrong on the others. A trailing `\n` from **double/triple-click** is dropped so that extra line box does not appear; Shift+arrows keep the newline so the mark can step onto the next line. Internal newlines in a multi-line mark stay. Double-click = word, another click = sentence, no trail. Emoji must stay a whole grapheme — never step a mark by one UTF-16 unit.

## Wiring checklist (`FormattedTextField`)

- [ ] `textDirection: resolveFieldTextDirection(text, ambient)`
- [ ] `textAlign: TextAlign.start` (follows direction)
- [ ] `wrapVisualCaretMotion(...)` always (identity actions when LTR)
- [ ] Primary pointer down stores global position; `onTap` calls `embedCaretForTap` **only on a collapsed single click** (not drag / mark / Shift+click / double-tap). Drags and Shift+click use `bidiAwareOffsetForEditable` (nearer visual edge / nearest run) so a number in Hebrew does not steal the mark. Phone long-press / double-tap word marks use the same geometry plus `wordSelectionAround` — not Flutter’s `getWordBoundary`.
- [ ] `selectionWidthStyle: BoxWidthStyle.tight` (desktop default `max` fills the line to the left in Hebrew)
- [ ] `strutStyle: AppTypography.fieldStrut` so color-emoji fallbacks do not shift lines without emoji
- [ ] Double/triple-click drops a trailing `\n`; Shift+arrows do not (that newline is how the mark steps to the next line)
- [ ] Object fields absorb `showOnScreen` so Shift+arrows do not hop the file pane
- [ ] Shift+arrows that extend across tasks/cells do not `requestFocus` the next field
- [ ] Cross-part arrow edge uses the **resolved** field direction, not only ambient locale
- [ ] Horizontal arrows flip only on an RTL glyph run (not on numbers / Latin)

## Super Editor (file body)

The file body is Super Editor, not `FormattedTextField`. Same direction rules apply:

| Rule | How |
|------|-----|
| Base direction | [`ambientAwareTextBuilders`](super_editor_text_direction.dart) — explicit node override, else shared writing preference (empty Hebrew paragraphs start RTL so the caret sits on the right). Do **not** use stock `getParagraphDirection` alone (it hard-codes empty → LTR). |
| Align | Stylesheet sets `TextAlign.start` (not absolute left/right) |
| Visual ←/→ | [`SuperEditorVisualCaretPlugin`](super_editor_visual_caret.dart) + `withVisualHorizontalSelectors` — same flip idea as `rtl_caret_motion.dart` (character/word; not Cmd+line / Home / End) |
| Tap / mark vs numbers in Hebrew | [`SuperEditorBidiCaretTapHandler`](super_editor_bidi_caret.dart) after the link handler: empty padding → logical end on a single tap. Glyph/gap clicks, Shift-click, double-tap and selection drags remain native to SE; no outer pointer listener rewrites the selection. |
| Selection wash | SE’s beneath-layer highlight is unreliable for RTL/Hebrew → [`selection_background_phase.dart`](../../editor/selection_background_phase.dart) also paints `BackgroundColorAttribution` on the selected span |
| iOS handles | [`ios_visual_handles.dart`](ios_visual_handles.dart) — upstream = logical start (top ball), downstream = logical end (bottom ball). Stems snap to the **tight** wash box nearest that document position (Hebrew: upstream on the right of the word). Super Editor’s one-character expansion is fallback only. |
| Phone mark | Handles only for enlarging. Double-tap / long-press start a word mark on the file body **and** object fields (object fields: BiDi-aware offset + Unicode word, same as a number-in-Hebrew caret). Double-tap on an empty / collapsed caret still opens the Cut/Copy/Paste bar. Body drag does not mark, so a swipe scrolls the file or changes page. Phone double-tap does not open a connected info (Info is on the mark bar). A tap on Super Editor body text leaves an open object (enter/leave pill is not the only exit). |

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
  test/files/rtl_paragraph_text_direction_test.dart \
  test/files/rtl_empty_space_caret_test.dart \
  test/files/phone_mark_toolbar_test.dart \
  test/files/line_range_selection_test.dart \
  test/files/rtl_super_editor_direction_test.dart \
  test/files/text_direction_override_test.dart \
  test/files/document_text_flow_test.dart \
  test/files/table_grid_nav_test.dart \
  test/files/table_cell_session_test.dart \
  test/files/ios_visual_handles_test.dart \
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
9. Numbers inside Hebrew — taps land at the line end (not after the number); marking a line does not start after the number. File body **and** object fields.

## Related

| Topic | Where |
|-------|--------|
| Continuous document / segments | [`../../AREA.md`](../../AREA.md) |
| Spans / mark / menus | [`../RICH_TEXT.md`](../RICH_TEXT.md) |
| Graph/table reading direction | Embed widgets use ambient `Directionality` for column mirroring — separate from this text-caret solution |
| Table grid ←/→ | [`../table_grid_nav.dart`](../table_grid_nav.dart) — physical pad/hardware arrows → visual cell. Grid RTL = app `Directionality` (col 0 on the right in Hebrew). Landing uses the destination cell’s first-strong direction so visual-right is logical start in RTL. Phone object-pad icons never mirror (UX chrome). |

### Rendered checks

`flutter test --dart-define=RTL_TEST_FONT=/path/to/HebrewFont.ttf test/files/rtl_rendered_geometry_test.dart`
loads the supplied font instead of Ahem. Without that argument these tests skip.
The SE test uses the installed `super_text_layout` (now an explicit dependency,
with no version upgrade). Object tests also dispatch real mouse taps beside each
line. Device font fallback, native IME, and handle comfort still need macOS/iOS
smoke testing. The logical line-end scan runs only for padding placement, not on
keystrokes or every selection update. It uses whole graphemes and excludes newline
characters; authored text is never changed.

SE's document layout exposes paragraph/list proxy components. Unwrap their public
`childTextComposable` before accessing text layout; use the leaf RenderBox for
global/local conversion. Otherwise `is TextComponentState` fails and silently
returns the stock hit (before a trailing number). Full-editor pointer regressions
cover these wrappers and indented lists, not just standalone SuperText geometry.

## Known difference — deferred by user (2026-09-08)

SE and object fields still differ around numbers/English at the end of an RTL
line. This is not optimal. Keep the comfortable object-field behavior and revisit
parity when there is time; do not expand the SE correction now. SE handles glyph
clicks (including affinity), inter-run gaps, Shift-click and drag selection natively.
Only a single click in empty line padding is intercepted for logical line end.
The body-focus handoff remains active so tapping SE can leave an object editor.

### Object pointer selection (2026-09-13)

Object fields use rendered grapheme boxes (`rtl/editable_pointer_selection.dart`) for mouse range endpoints and phone word selection. Mouse corrections run after Flutter's gesture callback in the same event turn, before paint; no correction runs while typing. Linked fields have no parent double-tap recognizer: a completed desktop double-click may open the hit link, while ordinary drags keep native focus and selection. Link hover bubbles close on pointer-down.

On iOS, single taps snap to the nearest word boundary, double-taps select the word, and swipes remain scrolling. Native handles still resize ranges. `rtl/editable_selection_controls.dart` adjusts their anchors to logical boundary graphemes instead of the visual order of mixed RTL/number boxes. The native caret is retained. Tests: `test/files/object_selection_regression_test.dart` (real Hebrew font via `RTL_TEST_FONT`, macOS Arial fallback), plus phone toolbar and cross-field selection tests. Physical-device font/IME behavior still needs smoke checking.
