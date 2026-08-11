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
| Escape inside an object | Returns SE caret to that object block |
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
4. **Escape** → place SE caret back on that embed block (`runNextFrame`).
5. While an inner field is focused, SE selection stays cleared (`openImeOnNonPrimaryFocusGain: false`).
6. Inner ↑/↓ only move between embed lines; edges do not leave the object.

| Embed | Inner lines (after Tab) |
|-------|---------------------------|
| Info | one field — first line is title (API/diagrams); rest is body |
| Task list | list title → each task |
| Table | cells row-major (`RichTableEditor`; chart tables share the same host) |
| Image | none — block only |

### Keystroke handoff

- **Tab / Escape** focus moves use `runNextFrame` (one frame).
- **Destructive** structure changes (empty Backspace deletes object/row) still use `runAfterKeystroke` so HardwareKeyboard can finish KeyUp.

### 3. Object remount

The file owns placement; the object owns content. Embed node ids are stable (`embed:<objectId>`). After move or reload, object UI must keep or re-seed payload from the in-memory embed cache — never dispose a live info editor into a blank cache entry.

## Move Mode

Double-click an embed to enter Move Mode (glass frame on the object). A floating glass bubble in the app [Overlay](embed_move_bubble.dart) (no scrim) has up / down / Done — drag the bubble to keep the document visible. Arrow presses keep the mode open; Done or tap outside the bubble ends it. Save writes pointer order back to marker text.
