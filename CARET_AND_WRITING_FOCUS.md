# Caret and writing focus

Gathered rules for **who owns typing**, **where the caret sits**, and **what must not remount while a key is down**. This file does not invent policy. Detail still lives in the docs linked from each section.

**Read this before changing** Super Editor, embeds, `AppState` notify paths, shells, `app.dart`, or any in-document `TextField`.

Canonical checklists that this file consolidates:

| Topic | Source of truth |
|-------|-----------------|
| Remount / notify / IME desync | [`NOTES.md` § Editor keyboard safety](NOTES.md#editor-keyboard-safety) |
| Fluent body + objects | [`FLUENT_TEXT.md`](system_app_front_end/lib/areas/files/editor/FLUENT_TEXT.md) |
| Files area (mark, multi-file caret, objects) | [files `AREA.md`](system_app_front_end/lib/areas/files/AREA.md) |
| Who rebuilds chrome vs the open document | [UX `AREA.md` § Who rebuilds](system_app_front_end/lib/areas/ux/AREA.md#who-rebuilds) |
| Hebrew caret / arrows | [`RTL.md`](system_app_front_end/lib/areas/files/rich_text/rtl/RTL.md) |
| Keystroke timing helpers | [`editor_key_handoff.dart`](system_app_front_end/lib/areas/files/editor/editor_key_handoff.dart) |

---

## 1. What the user should feel

A file is **one continuous piece of text**. Paragraphs, lists, tables, and objects sit in that same flow. The user should never feel that they clicked into a nested widget to keep writing.

**Per keystroke:** Super Editor inserts into the in-memory document (grapheme snap only if a mark splits an emoji). Save is the existing ~450ms debounce. Do not notify phone object-pill chrome unless enter/leave changed. Do not run OS autocorrect / suggestions / spellcheck on the file body or object fields.

**Parts are lines.** A bullet, a table row, and an embed (or each of its editable inner parts, once the object is open) count as one line of the document. Any caret or marking decision is settled by asking what a plain line would do. A caret that stalls at a boundary, or a delete that leaves an empty bullet or blank gap, is a bug — not a widget detail. Inner mark-delete of every task or table row is the exception: one empty part stays so the object is not destroyed from the inside (chrome or empty Backspace on the last unit still deletes it).

A blank line the user typed is text and is saved. Move and delete must not leave empty paragraphs the user did not make.

A tap **on glyphs** in a table cell, task, or info stays on that glyph. Padding beside the line jumps to the logical end **on a click**. A drag or Shift+click keeps the user’s mark (do not snap it to the whole line) and uses the nearer visual edge / nearest run so a number in Hebrew does not steal the start. Gaps between Hebrew and numbers snap to the nearest glyph. End-of-line taps keep the caret on that line.

---

## 2. Writing in objects

Super Editor is a package. Almost all of **our** writing work is inside objects: a Material [`FormattedTextField`](system_app_front_end/lib/areas/files/rich_text/formatted_text_field.dart). Flutter paints the caret. Do not imitate Super Editor’s caret painter.

| Surface | What it is | Who owns the caret |
|---------|------------|--------------------|
| File body | Super Editor (`SuperDocumentEditor`) — package | Super Editor composer + [`DocumentCaretSession`](system_app_front_end/lib/areas/files/editor/document_caret_session.dart) |
| Inside an object | `FormattedTextField` (info, tasks, cells, captions) | That field’s `FocusNode`, via [`BlockTextFocusRegistry`](system_app_front_end/lib/areas/files/rich_text/block_text_focus.dart) |

Only **one** of those owns typing at a time (`DocumentCaretOwner.document` vs `embed`). While an inner field is focused:

- Super Editor selection and Super Editor focus stay cleared.
- `openImeOnNonPrimaryFocusGain` is false, so SuperIme does not steal the IME from the field.
- Insert must not `notifyListeners` mid-handoff or the IME dies after one character.

### Rules (every inner field)

| Do | Don't |
|----|--------|
| Leave the native caret (`showCursor` on) | Hide the cursor and overlay-paint a bar |
| Place the caret on a **click** with [`embedCaretForTap`](system_app_front_end/lib/areas/files/rich_text/rtl/embed_caret_hit.dart) in the same turn | Write `controller.selection` on keystrokes, inbound refresh, or mouse-up after a drag that was already a mark |
| Hebrew: tap **on glyphs** stays; empty padding beside the line → logical end **only for a collapsed click**; drag / Shift+click use nearer visual edge / nearest run | Apply padding→line-end on a drag, an existing mark, or Shift+click (that is the Hebrew “whole line immediately” bug). Let a number in Hebrew steal the mark start |
| Expand to the caret line only when resolving an **unmarked action** (right-click / format / AI) | Expand-to-line while the user is marking |
| `maxLines: null` even for one visual line; strip newlines where a single line is required | `maxLines: 1` (vertical intents mark the whole field) |
| Silent saves (`notify: false`); stable widget keys; skip reseed while the field is focused | Remount or `setRichState` a focused field (caret jumps to the end) |
| `TextField.style` at least as large as the largest painted run | Body-sized field style under a larger title run (Hebrew hit-test treats glyphs as padding) |
| One [`DocumentTextFlow`](system_app_front_end/lib/areas/files/editor/document_text_flow.dart) per **multi-field** object | A flow on a single-field object (info); marks across objects or into the file body |
| File pane owns scrolling; object fields never call `ensureVisible` and never propagate `showOnScreen` | `ensureVisible` / `showOnScreen` on focus or Shift+arrows (the text hops up then down) |
| Install `onKeyEvent` **once**; visual ←/→ via `Actions` | Re-wrap `onKeyEvent` on rebuild; reimplement arrows in `onKeyEvent` |
| Keyboard safety in [`NOTES.md`](NOTES.md#editor-keyboard-safety) | `notifyListeners` from a keystroke |

Keep-focus: the **bottom menu** and the **open object**. Tap the file canvas / body (not another field): unfocus, hide the caret, **clear the mark**. Tap the open object’s frame: keep typing.

### Moving between objects and Super Editor

Only **one** surface owns writing, and only **one** mark is painted. Super Editor’s `FocusNode.hasFocus` is also true when a descendant field is focused — that must not count as “the body owns writing.” Use **primary** focus.

| Gesture | Who owns writing | What happens to the other surface |
|---------|------------------|-----------------------------------|
| Click or right-click a **paragraph / list line** | Super Editor body | Object mark and caret are forgotten (collapsed, not frozen into the body menu). Right-click expands to that body line for the action. |
| Click or right-click an **inner field** | That field | Super Editor caret and mark are cleared (`adoptEmbed`). Right-click focuses the field first, then freezes the mark or caret line. |
| Right-click **object chrome** (not text) | Block / chrome menu | Whole-object menu. Inner-field mark is not the target. |
| **Shift+Enter** on the block | Opens the object | Same as §4. |
| **Enter** inside | Leave (info) or next item; Escape leaves from any field; Shift+Enter / ⌘Enter is a newline | Same as §4. |
| Tap **canvas** outside the file card | Nobody | Hide caret, clear every mark. |
| Tap **empty space in the file** (below the last line) | Super Editor body | Caret at the **end** of the last block. |

Never paint an object-field wash and a Super Editor line wash at the same time. Opening the body menu must not freeze a leftover object mark (`releaseLiveMark` before `openMenuSession`).

A **new** right-click, anywhere, retargets even while the previous right-click menu is still open: close that freeze (`beginNewPointerAim`), mark the new line, open the new menu. The first menu’s `openMenuSession` completing later must not keep the old freeze or restore the old caret. Putting the caret in another file or object while that menu is open (or as it closes) drops the auto-marked line — the freeze belongs to the field that opened the menu, not whoever owns writing now.

Enter inside info leaves the object. **Escape** leaves from any inner field. **Shift+Enter** / **⌘Enter** / Ctrl+Enter inserts a newline. Tasks / table cells keep structural Enter; those same modifiers insert a newline in that field. Shift+Enter on the object **block** still opens it.

### Per type

| Object | Inner fields | Flow | Notes |
|--------|--------------|------|--------|
| Info | One field (first line = title, rest = body) | None | Do not reseed while focused. Freeze the **mark or caret line** for the field menu — not the whole object. |
| Task list | List title + one field per task | One `DocumentTextFlow` | Stable row keys when a pending id arrives. Shift+arrows / Shift+click mark across tasks in that list only. |
| Table / chart | One field per cell | One `DocumentTextFlow` | Do not reseed a focused cell. Grid ←/→ is [`table_grid_nav.dart`](system_app_front_end/lib/areas/files/rich_text/table_grid_nav.dart). |
| Image | Optional captions | None | Same field rules; `stripNewlines`. Picture is block-only. |
| Map open card | Title + body | None | Title: `maxLines: null` + strip newlines (not `maxLines: 1`). |

---

## 3. Claim vs caret vs IME

A topic can show several files, so several Super Editors are mounted at once.

| Idea | Rule |
|------|------|
| **Claim** | Last file the user clicked or typed in (`DocumentEditorRegistry.claim`). Inserts and AI target this file even if the caret is hidden. |
| **Caret paint** | Only the file that is **claimed and has primary focus** draws a caret. A focused object field is a descendant — Super Editor `hasFocus` is not enough or you get two carets. Switching files releases the previous pane’s mark. Tap-outside clears the mark. |
| **IME role** | Every editor gets `inputRole: 'file-<id>'`. Without a unique role the panes fight one global IME connection. |
| **Hiding the caret** | Swap Super Editor cursor overlay layers for empty layers of the **same count**. Removing a layer or styling the caret transparent does not work (`ContentLayers` / blink controller). |

Claim follows the click. The visible caret follows primary focus. Tap-outside, a dialog, or another field hides the caret.

After chrome that stole the keyboard (arrange, task/table reorder, Move Mode), `DocumentEditorRegistry.restoreActiveWritingFocus()` puts it back on the next frame. Tap-outside does **not** restore.

**Tap outside** the focused editor (canvas / empty padding — not another field) unfocuses, hides the caret, **clears the mark**, and closes the keyboard. The **bottom menu** is excluded so insert tools stay usable while typing. An **open object** is excluded so a tap on its frame does not kill the inner field.

---

## 4. Objects: on the block vs inside

Objects are **atomic Super Editor blocks**. Arrows do **not** auto-enter or auto-leave. That fought two IMEs.

| Gesture | Result |
|---------|--------|
| ↑/↓ in the file body | Moves through paragraphs and object blocks as units |
| Click an inner field, or **Shift+Enter** on the block | Opens the object (first inner field); Super Editor caret is cleared |
| Click / right-click a paragraph | Body owns writing; object mark and caret are forgotten |
| Right-click an inner field | Field owns writing (focus + caret at the pointer); Super Editor caret is cleared |
| **Enter** on the block | New paragraph **below** the object |
| **Enter** inside info | Unfocus the field; place Super Editor caret on a text node **after** the object (insert an empty paragraph if needed); `requestFocus` next frame |
| **Escape** inside | Same leave as info Enter, from any inner field (tasks, cells, captions) |
| **Shift+Enter** / **⌘Enter** inside | Newline in the field |
| ↑/↓ inside an open object | Stay inside that object’s lines |
| Image | Captions are inner fields; the picture is block only |

**Phone** has no Shift+Enter or Escape key. The first bottom-bar pill is arrows plus enter/leave. Those arrow **icons** never mirror in Hebrew (physical left stays left). Table **cells** still flip with the Hebrew UI.

After insert, the caret enters the new object’s first inner field. Images without a caption keep the block caret. Insert bar and **Insert object** shortcuts must do this **without** a shell-wide `notifyListeners`.

Timing:

- **Anything that changes the focused editor** (Shift+Enter enter, Escape leave, empty Backspace deletes, remount, restore writing focus) → `runWhenKeyboardIdle`.
- **Layout / IME wiring** after keys are already idle → `runNextFrame` (one frame).

Phone IME: iOS will not send Enter / empty Backspace as `KeyEvent`s. `FormattedTextField` maps a single IME newline to Enter, and a second delete on an empty unit to empty Backspace — same structure rules as desktop. Keep the keyboard up when moving between inner fields.

---

## 5. One marking

Every action (right-click, clipboard, format, Make link, AI `selected_text`) uses **one** rule:

1. If anything is marked, that span is the target (across as many parts as it covers).
2. If nothing is marked, the target is the **line at the caret**.

Never read a single field’s `TextEditingController.selection` to decide what an action affects.

**Freeze before focus loss.** Opening a menu or dialog can collapse Super Editor selection.

- Right-click: place the caret at the pointer (unless the click is inside an existing mark), expand to that line, then capture and freeze. Object fields use this same sequence — a leftover snapshot on the field must not win. Mouse **marking** (drag / Shift+click) must not expand to the line.
- Agent prompt / saved AI actions: `DocumentEditorRegistry.captureMarkedTextForAgent()` **before** the dialog opens. An embed mark is used only while that field owns typing (or tap-outside left no Super Editor selection). A leftover object field must not win once the body has a mark.

While a menu is open there is never a second wash (native selection + line-at-caret) at the same time.

---

## 6. Where typing must not die (keyboard safety)

Flutter desyncs when a `TextField` / `FocusNode` is disposed or the editor remounts **while a physical key is still down**.

Symptom: looping `KeyDownEvent is dispatched, but the state shows that the physical key is already pressed` or `KeyUpEvent … physical key is not pressed`.

**The gate:** [`runWhenKeyboardIdle`](system_app_front_end/lib/areas/files/editor/editor_key_handoff.dart). Every remount / unfocus / `requestFocus` / dispose / notify of a focused editor must use it. Do not check `physicalKeysPressed` ad hoc. `runAfterKeystroke` is an alias. `runNextFrame` is layout/IME only after keys are idle. Cycle-files chrome is the exception.

**Structure:** chrome may rebuild; the **open document stays mounted**. Incoming body / embed updates apply **into** the open editor. Do not wrap `DocumentEditor` / `SuperDocumentEditor` in `ListenableBuilder(listenable: appState)`. Do not rebuild `MaterialApp` or the topic canvas on every `AppState` notify.

**iOS has no `physicalKeysPressed` while typing.** Payload-only embed refresh or remounting a `TextField` (conditional parent around the field) drops focus after the first letter even with no keys-down check to catch it.

### MUST NOT

1. Rebuild `MaterialApp`, `AppShell`, or the topic canvas on every `notifyListeners`.
2. `notifyListeners()` / `loadEmbedsForFile(notify: true)` from a keystroke path (`onChanged`, every character).
3. `setState` Super Editor, replace `Editor`, or remount embeds while keys are down — unless the change is purely visual and keeps the same `FocusNode`s. On phone, payload-only list replacements must not `setState` the editor at all.
4. Dispose or recreate cell / task / info `FocusNode`s / controllers in `didUpdateWidget` while those fields have focus or keys are down.
5. Overwrite live controller text from a stale embed cache while the user is typing (dirty). A **clean** embed takes a newer inbound payload **after keys are up**. Dispose must not flush an old payload over inbound.
6. Notify listeners from a registry’s `dispose` (tree is locked).
7. Swap `Editor` in place after a silent reload without remounting `SuperEditor` (`ValueKey` epoch) — the orphan `DocumentImeInputClient` keeps a dead `Document`.

### MUST

1. Silent saves: document + object payload/title patches use `notify: false` (or patch cache in place).
2. Debounce embed PATCHes (~400ms). Never hit the network on every character without a timer.
3. Patch cache **before** `await` so a remount cannot re-seed empty content mid-flight.
4. Rebuild Super Editor only for **structural** embed changes (id / type / order). If a structural rebuild is required, `runWhenKeyboardIdle`.
5. Stable embed identities (`embed:<objectId>`, `GlobalKey` where State must survive parent rebuilds).
6. Registries bump through [`FrameSafeNotifier`](system_app_front_end/lib/shared/utils/frame_safe_notifier.dart): notify now when the tree is free; wait for end of frame when it is locked. Waiting always is wrong — post-frame callbacks do not schedule a frame, so an idle bump would never arrive.
7. `wrapVisualCaretMotion` always keeps an `Actions` parent (same tree shape so an IME language switch does not remount the field). `TableEmbed` must not `setState` on text-only emits.
8. After arrange / reorder / Move Mode, restore writing focus with `runWhenKeyboardIdle`.
9. On launch / hot restart, drop engine-seeded pressed keys while the loading pane is showing (`hardware_keyboard_guard.dart`). Never `HardwareKeyboard.clearState` (it wipes handlers).

### Who rebuilds (chrome vs document)

| Change | What rebuilds |
|--------|----------------|
| Language | `app.dart` rebuilds `MaterialApp` only |
| Document text size | Same — `app.dart` rebuilds `MaterialApp`; `TopicView` also listens |
| Sidebar, mode, canvas wash, bottom bar | Shell listen — chrome only. `TopicView` is a **stable child** |
| Open topic, file list / names / order, layout | `TopicView` listens itself |
| Document body or embeds | `SuperDocumentEditor` listens itself and applies into the open editor. If a key is down, the apply waits |
| Launch | Last topic + sidebar paint from a disk snapshot; network refresh does not clobber a dirty editor |

### Smoke-check after editor edits

Type quickly in: paragraph, info body, task title, table cell, chart-table cell. Shift+Enter into an object, type, Escape out, type below. If the assertion appears: **full restart** (hot reload can leave keys stuck), then fix the remount/notify path.

---

## 7. Insert, Enter, Backspace (structure)

| Context | Key | Behavior |
|---------|-----|----------|
| Paragraph | Enter | New line **in the same paragraph** — never splits the block |
| Paragraph | Backspace at start of empty block | Remove the stub / merge into the previous paragraph |
| List | Enter on a filled item | New item |
| List | Enter on an empty item | Drop that item, continue as a paragraph below (list stays) |
| List | Backspace on an empty item | Remove the item, or exit the list if it was the last |
| Empty list item / table row / trailing object unit + **Enter** | Exit that structure **without destroying it** |
| Empty object (empty info, last empty task, last empty graph column) + **Backspace** | **Remove** the object, coalesce surrounding text |
| Insert object | Last-claimed file, at the caret (blank lines included). Mid-paragraph splits `before \| new \| after`. List / table / embed carets insert after the containing block |

A newly inserted list or table gets the caret in its first bullet or top-left cell.

---

## 8. Several files, shortcuts, RTL

**New file:** added first so it is on screen; the caret lands in it.

**Opening a topic:** the caret lands at the **end** of the first file on that page (desktop: first shown file; phone: the first swipe page).

**Cycle files (⌘[ ⌘]):** rotates every live file in the topic. Applies immediately — do **not** wait for KeyUp / `runWhenKeyboardIdle` (that stall is for editor mutations, not chrome).

**Shortcuts:** non-text shortcuts are taken at the hardware keyboard (work without a caret; the editor cannot swallow them). Text shortcuts still need a caret. A press fires once: ignore a second delivery until KeyUp (size up/down may repeat).

**RTL:** only [`rich_text/rtl/`](system_app_front_end/lib/areas/files/rich_text/rtl/). Do not add competing caret math in `DocumentTextFlow` or embed widgets.

- Base direction = first strong character, else ambient UI.
- Visual ←/→ inside a field: flip intents, do not reimplement arrows.
- Empty padding tap → logical line end in the same event turn (never post-frame).
- Empty space under the file (the leftover pane below the last block) → logical end of the last part. That area is a `SliverFillRemaining` so it stays tappable; it is not tap-outside.
- Cmd+arrow / Home / End in Hebrew are a known gap (shared intents; flipping would break Home/End).

Table grid ←/→ is only [`table_grid_nav.dart`](system_app_front_end/lib/areas/files/rich_text/table_grid_nav.dart): physical pad → visual cell. In-cell caret is first-strong RTL, not grid RTL.

---

## 9. Known unfinished (already on the backlog)

These are defined as **not done**, not as rules to implement around:

- Marks do not cross objects or into the Super Editor body ([`BACKLOG.md`](BACKLOG.md) O3 / leftover E6).
- Deleting across parts does not merge the first and last part into one.
- Cmd+arrow and Home/End in Hebrew.
- Undo/redo is per Super Editor document, not one stack shared with cross-part embed edits.

The dual model (Super Editor body + embed `TextField`s + leftover flow/mark code) is the main source of “caret chaos”: two IMEs, two focus trees, and a handoff that must never remount mid-keystroke.
