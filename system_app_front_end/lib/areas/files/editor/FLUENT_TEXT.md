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

A bullet, a table row, and an **embed** (or each of its editable parts — info title/body, task row, graph column) count as **one line** of the document. Settle caret and marking questions by asking what a plain line would do.

| Situation | Because a part is a line |
|-----------|--------------------------|
| Arrow up into whatever is above | Lands on its **last** line / end of last part |
| Arrow down into whatever is below | Lands on its **first** line / start of first part |
| Delete an object | Caret stays at the **end** of the text that was above it |
| Marking a whole object and deleting | The object goes, like deleting a marked line |

## Three principles

### 1. No empty neighbors

After move, delete, or split, never leave an empty or whitespace/`\n`-only paragraph beside an embed (or stranded between text halves). The bridge serializer drops spacer/empty parts adjacent to pointers.

Blank lines the user wants live as `\n` **inside** a paragraph — not as empty sibling blocks.

### 2. Edge landing

Approach from below → **end / last line** of what is above. Approach from above → **start / first line** of what is below. Super Editor owns caret movement across text nodes; embeds keep their own internal fields.

### 3. Object remount

The file owns placement; the object owns content. Embed node ids are stable (`embed:<objectId>`). After move or reload, object UI must keep or re-seed payload from the in-memory embed cache — never dispose a live info editor into a blank cache entry.

## Move Mode

Double-click an embed to enter Move Mode (glass frame). Use the move toolbar (up / down / Done) to reorder; save writes pointer order back to marker text.
