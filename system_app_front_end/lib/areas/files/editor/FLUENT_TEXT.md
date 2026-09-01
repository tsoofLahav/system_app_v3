# Fluent text with objects

How the file editor keeps **one continuous piece of text** when lists, tables, and embedded objects sit inside it.

**Storage dialect** (marker text SoT, pointer embeds): [`DOCUMENT_TEXT.md`](DOCUMENT_TEXT.md).

**Editing surface:** Super Editor ([`super_document_editor.dart`](super_document_editor.dart)). Bridge save keeps the document as the user left it, blank lines included.

Sibling policy docs: caret/RTL → [`../rich_text/rtl/RTL.md`](../rich_text/rtl/RTL.md). Area overview → [`../AREA.md`](../AREA.md).

## Boundary

| Layer | Owns |
|-------|------|
| Marker text + SE bridge | Persisted placement; the save path changes nothing the user can see |
| Super Editor `MutableDocument` | In-session structure, typing, list items, undo |
| Embed widgets + [`AppState`](../../../../core/app_state.dart) | Object **payload** (info body, tasks, table rows, …). Marker text stores pointer lines only |

## Parts are lines

A bullet, a table row, and an **embed block** count as **one line** of the document for Super Editor’s caret. Inside an object, tasks/cells (and info’s soft-wrapped lines) are separate lines — but only after you open the object.

| Situation | Behavior |
|-----------|----------|
| ↑/↓ in document text | Moves through paragraphs and **object blocks** as atomic units |
| Tab on an object block | (does not open — Shift+Enter does) |
| Shift+Enter on an object block | Opens the object (first inner field); click also works |
| Enter on an object block | New paragraph **above** the object when the caret is on its leading edge (upstream / before), **below** when it is on the trailing edge |
| Shift+Enter inside an object | Newline in the field |
| Escape inside an object | Leaves to the line after the object. Phone: leave icon on the first bottom-bar pill |
| Enter inside an object | Info: leave. Tasks / lists / table cells: new item / next cell. Phone IME Return is the same structure key |
| ⌘Enter / Ctrl+Enter inside an object | Newline in the field (captions that strip newlines swallow it) |
| Click / right-click a paragraph | Body owns writing; object mark and caret are forgotten. One mark only |
| Click / right-click an inner field | Field owns writing; Super Editor caret is cleared. Right-click focuses the field first |
| Right-click while a menu is already open | Retarget: mark the new line and open **its** menu (`beginNewPointerAim`). Not nested on the old freeze |
| ↑/↓ inside an open object | Moves between that object’s lines only (does not leave). Shift+arrows mark across tasks, or a **rectangle of cells** (Shift+↑/↓ and Shift+←/→). Coming from below lands at the end of the line (fluent text). Phone: keep the keyboard up across inner fields |
| Delete a marked object | Object goes, like deleting a marked line |
| Delete a fully marked task / table row | The task or row is removed, not left empty. If every inner part is marked, one empty part stays — delete the object from chrome or empty Backspace on the last unit |
| Paste inside an object | Inserts at the caret. A marking still replaces. **Task titles:** a multi-line paste (newlines or `;`) becomes one task per line — first line stays in the focused row, the rest are created after it |

## Three principles

### 1. A blank line is text

A gap the user typed is part of the file, wherever it sits — between two paragraphs, beside an object, or at the end. Empty paragraphs are saved as `[SPACER n="1"]` parts and come back as empty paragraphs, so what is on screen and what is on disk have the same number of lines.

That equality is what makes insertion land right: the insert bar turns the caret's node index into a marker part index ([`markerGapIndexForNodeIndex`](../model/marker_super_editor_bridge.dart)), and the server inserts the pointer between stored parts. When the save dropped trailing blanks, the two counts drifted and an object typed under a gap reappeared under the last paragraph.

The one thing the save still decides on its own: leading blanks are dropped (a file cannot start on air, and a new file is one empty paragraph), and a file that is nothing but blanks is an empty file — the same rule the backend applies.

Move and delete clean up after themselves instead: never *leave* an empty paragraph the user did not make.

### 2. Atomic objects + explicit enter/exit

Objects are **one Super Editor block**. The document caret never auto-enters via arrows (that fought two IMEs).

Mechanism ([`embed_caret_bridge.dart`](embed_caret_bridge.dart) + [`document_caret_session.dart`](document_caret_session.dart)):

1. SE selection on `ObjectEmbedNode` = “on this object” (block wash).
2. **Shift+Enter** → open object ([`runWhenKeyboardIdle`](editor_key_handoff.dart), then one layout frame). Clicking a field also opens it.
3. **Enter** on the block → empty paragraph before the object when the caret is upstream, after it when downstream (same as Super Editor’s binary-node newline).
4. **Escape** inside any inner field (and **Enter** inside info / empty structure units) leaves: unfocus the embed field, place SE caret on a **TextNode after** the embed (insert empty paragraph if needed), then `requestFocus` on the next frame so SuperIme opens only against a live node. **Shift+Enter** / **⌘Enter** inside insert a newline.
5. While an inner field is focused, SE selection and SE focus stay cleared (`adoptEmbed` unfocuses the editor; `openImeOnNonPrimaryFocusGain: false`). Insert must not `notifyListeners` mid-handoff or the IME dies after one character.
6. Silent document reload that **replaces** `Editor` must remount `SuperEditor` (`ValueKey` epoch). SE recreates `DocumentImeInputClient` on `editContext` change without disposing the old client; the orphan keeps the dead `Document` while the shared composer selection points at new node ids → `selectUpstreamPosition` null-check crash on Escape/IME open.
7. Inner ↑/↓ only move between embed lines; edges do not leave the object.

| Embed | Inner lines (after Shift+Enter) |
|-------|---------------------------|
| Info | one field — first line is title (API/diagrams); rest is body. **Escape** or **Enter** leaves the object; **Shift+Enter** / **⌘Enter** / Ctrl+Enter inserts a newline. Do not reseed while focused. Caret/mark: [`CARET_AND_WRITING_FOCUS.md`](../../../../../CARET_AND_WRITING_FOCUS.md) § Writing in objects |
| Task list | list title → each task |
| Table / chart grid | Physical 2D cells. Product rules (Enter, add-after, reorder, empty Backspace): files [`AREA.md` § Tables & charts](../AREA.md#tables--charts). Caret: [`table_grid_nav.dart`](../rich_text/table_grid_nav.dart) is the only physical→visual cell move (pad + hardware + edge exit). Hebrew UI flips columns; the phone pad does not. Landing is the visual edge entered from, converted with the destination cell’s first-strong direction (RTL visual-right = logical start). Empty Backspace steps to the previous cell; first cell of an empty row removes the row. One `FocusNode` per cell. Document enter/exit still uses row-major `focusLine` |
| Image | optional captions (`FormattedTextField`, strip newlines); picture is block-only |
| Map open card | title + body (title is one visual line: `maxLines: null` + strip newlines) |

### Keystroke handoff

- **Anything that remounts, unfocuses, `requestFocus`es, disposes, or notifies a focused editor** must go through [`runWhenKeyboardIdle`](editor_key_handoff.dart). If no physical key is down it runs now; if a key is down it waits for KeyUp. Shift+Enter enter, Escape leave, empty Backspace deletes, embed structure rebuilds, and restoring writing focus all use it.
- **Layout / IME wiring** after keys are already idle may still use `runNextFrame` (one frame so SuperIme opens against a live node).
- **Phone IME:** Return inserts a newline (iOS ignores `textInputAction` on multiline fields) and empty-field delete is a no-op in the engine. [`FormattedTextField`](../rich_text/formatted_text_field.dart) treats a single IME newline as Enter, and holds an invisible sentinel so a second delete on an empty unit is empty Backspace. Same task / list / table / info rules as desktop. iOS reports no physical keys, so `runWhenKeyboardIdle` runs immediately — do not remount a `TextField` on IME.
- Mid-keystroke remounts (AppState notify, embed list reload, disposing cell `FocusNode`s) cause `KeyDownEvent … already pressed` / `KeyUpEvent … not pressed`. Full MUST / MUST NOT checklist: [`NOTES.md` § Editor keyboard safety](../../../../../../NOTES.md#editor-keyboard-safety) and files [`AREA.md`](../AREA.md#keyboard--focus-safety-recurring-bug-class).

### Object right-click menus

Each object type keeps its own menu (not the plain paragraph menu):

| Object | Menu |
|--------|------|
| Info | Text + **Connect info…** / **Remove connection**; chrome **Add tag** / **Add connection** / **Design…** / **Move object** |
| Task list | Text + **Connect info…** / **Remove connection** + **Choose view…** / **Reorder tasks** / **Move object** |
| Table | Text + **Add row/column after** + **Reorder rows…** / **Reorder columns…** + **Design…** (+ Connect info / Remove connection when wired). Chrome includes **Move object**; cell menus do not. |
| Chart table | **Design…** (look, chart type, colours) + **Reorder columns…**; block caret → chart menu + **Move object** |
| Image | **Move object** + **Design…** + **Make smaller / larger** + **Tiny / Quarter / Half / Full size** |

Embed fields mark [`DocumentSecondaryTap`](document_secondary_tap.dart) **for that pointer** so Super Editor’s translucent secondary-tap handler does not open a second menu on the same click. A new right-click is a new pointer and is not swallowed by an open field menu. Right-click on an object block (SE caret on the embed) resolves the node under the pointer and opens that object’s menu.

### 3. Object remount

The file owns placement; the object owns content. Embed node ids are stable (`embed:<objectId>`). After move or reload, object UI must keep or re-seed payload from the in-memory embed cache — never dispose a live info editor into a blank cache entry. A clean (not dirty) graph/info takes a newer inbound payload; dispose must not write the old local copy over it. If the user and the agent both changed the **same** object or the file body, ask which to keep. Different objects in the same file do not open that dialog.

## Move Mode

Enter from the object chrome menu (**Move object**) or **⌘⇧O** when the caret or last-interacted embed is an object (glass frame on the object). Double-click selects a word in inner fields. A floating glass bubble in the app [Overlay](embed_move_bubble.dart) (no scrim) has up / down / Done — drag the bubble to keep the document visible. Arrow presses keep the mode open; Done or tap outside the bubble ends it. Save writes pointer order back to marker text.
