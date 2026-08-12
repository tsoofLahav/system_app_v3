# Fluent text with objects

How the file editor keeps **one continuous piece of text** when lists, tables, and embedded objects sit inside it.

**Storage dialect** (marker text SoT, pointer embeds): [`DOCUMENT_TEXT.md`](DOCUMENT_TEXT.md).

**Editing surface:** Super Editor ([`super_document_editor.dart`](super_document_editor.dart)). Bridge save prunes empty neighbors around embeds.

Sibling policy docs: caret/RTL → [`../rich_text/rtl/RTL.md`](../rich_text/rtl/RTL.md). Area overview → [`../AREA.md`](../AREA.md).

## Boundary

| Layer | Owns |
|-------|------|
| Marker text + SE bridge | Persisted placement; save path drops blank neighbors next to embeds |
| Super Editor `MutableDocument` | In-session structure, typing, list items, undo |
| Embed widgets + [`AppState`](../../../../core/app_state.dart) | Object **payload** (info body, tasks, table rows, …). Marker text stores pointer lines only |

## Parts are lines

A bullet, a table row, and an **embed block** count as **one line** of the document for Super Editor’s caret. Inside an object, tasks/cells (and info’s soft-wrapped lines) are separate lines — but only after you open the object.

| Situation | Behavior |
|-----------|----------|
| ↑/↓ in document text | Moves through paragraphs and **object blocks** as atomic units |
| Tab on an object block | Opens the object (first inner field); click also works |
| Enter on an object block | New paragraph **below** the object (keep writing) |
| Escape inside an object | SE caret **after** the object (downstream / empty paragraph below) so typing continues under it |
| ↑/↓ inside an open object | Moves between that object’s lines only (does not leave) |
| Delete a marked object | Object goes, like deleting a marked line |

## Three principles

### 1. No empty neighbors

After move, delete, or split, never leave an empty or whitespace/`\n`-only paragraph beside an embed. The bridge serializer drops spacer/empty parts adjacent to pointers.

Blank lines the user wants live as `\n` **inside** a paragraph — not as empty sibling blocks.

### 2. Atomic objects + explicit enter/exit

Objects are **one Super Editor block**. The document caret never auto-enters via arrows (that fought two IMEs).

Mechanism ([`embed_caret_bridge.dart`](embed_caret_bridge.dart) + [`document_caret_session.dart`](document_caret_session.dart)):

1. SE selection on `ObjectEmbedNode` = “on this object” (block wash).
2. **Tab** (keyboard + macOS `insertTab:`) → open object ([`runNextFrame`](editor_key_handoff.dart)). Clicking a field also opens it.
3. **Enter** on the block → normal SE newline below the object.
4. **Escape** → unfocus the embed field, place SE caret on a **TextNode after** the embed (insert empty paragraph if needed), then `requestFocus` on the next frame so SuperIme opens only against a live node.
5. While an inner field is focused, SE selection and SE focus stay cleared (`adoptEmbed` unfocuses the editor; `openImeOnNonPrimaryFocusGain: false`). Insert must not `notifyListeners` mid-handoff or the IME dies after one character.
6. Silent document reload that **replaces** `Editor` must remount `SuperEditor` (`ValueKey` epoch). SE recreates `DocumentImeInputClient` on `editContext` change without disposing the old client; the orphan keeps the dead `Document` while the shared composer selection points at new node ids → `selectUpstreamPosition` null-check crash on Escape/IME open.
6. Inner ↑/↓ only move between embed lines; edges do not leave the object.

| Embed | Inner lines (after Tab) |
|-------|---------------------------|
| Info | one field — first line is title (API/diagrams); rest is body |
| Task list | list title → each task |
| Table / chart grid | Physical 2D cells. Product rules (Enter, add-after, reorder): files [`AREA.md` § Tables & charts](../AREA.md#tables--charts). Caret: `hostKeyEvent` owns ←/→ (edge → side cell; RTL flips cols); ↑/↓ first/last line → cell above/below; one `FocusNode` per cell; surgical focus insert on add-column; chart parent rebuild deferred one frame. Document enter/exit still uses row-major `focusLine` |
| Image | none — block only |

### Keystroke handoff

- **Tab / Escape** focus moves use `runNextFrame` (one frame).
- **Destructive** structure changes (empty Backspace deletes object/row) still use `runAfterKeystroke` so HardwareKeyboard can finish KeyUp.
- Mid-keystroke remounts (AppState notify, embed list reload, disposing cell `FocusNode`s) cause `KeyDownEvent … already pressed`. Full MUST / MUST NOT checklist: [`DEVELOPMENT.md` § Editor keyboard safety](../../../../../../DEVELOPMENT.md#editor-keyboard-safety-read-before-editing-the-file-editor) and files [`AREA.md`](../AREA.md#keyboard--focus-safety-recurring-bug-class).

### Object right-click menus

Each object type keeps its own menu (not the plain paragraph menu):

| Object | Menu |
|--------|------|
| Info | Text + **Add tag** / **Add connection** |
| Task list | Text + **Choose view…** / **Reorder tasks** |
| Table | Text + **Add row/column after** + **Reorder rows…** / **Reorder columns…** (+ Connect info when wired) |
| Chart table | **Reorder columns…** + chart type + palette (on chart chrome **and** cells); block caret → chart menu |

Embed fields mark [`DocumentSecondaryTap`](document_secondary_tap.dart) so Super Editor’s translucent secondary-tap handler does not open a second menu. Right-click on an object block (SE caret on the embed) resolves the node under the pointer and opens that object’s menu.

### 3. Object remount

The file owns placement; the object owns content. Embed node ids are stable (`embed:<objectId>`). After move or reload, object UI must keep or re-seed payload from the in-memory embed cache — never dispose a live info editor into a blank cache entry.

## Move Mode

Double-click an embed to enter Move Mode (glass frame on the object). A floating glass bubble in the app [Overlay](embed_move_bubble.dart) (no scrim) has up / down / Done — drag the bubble to keep the document visible. Arrow presses keep the mode open; Done or tap outside the bubble ends it. Save writes pointer order back to marker text.
