# Fluent text with objects

How the file editor keeps **one continuous piece of text** when lists, tables, and embedded objects sit inside it.

**Storage dialect** (marker text SoT, pointer embeds): [`DOCUMENT_TEXT.md`](DOCUMENT_TEXT.md).

Sibling policy docs: caret/RTL → [`../rich_text/rtl/RTL.md`](../rich_text/rtl/RTL.md). Area overview → [`../AREA.md`](../AREA.md).

## Boundary

| Layer | Owns |
|-------|------|
| [`DocumentBuffer`](../model/document_buffer.dart) | Marker-text SoT; Move Mode = pointer cut/paste; reindex drops blank neighbors next to embeds |
| [`DocumentSession`](document_session.dart) + coalesce | Structural exits/prune/delete (folded into the buffer on commit) |
| [`DocumentTextFlow`](document_text_flow.dart) | Segment order + part `baseOffset`; ↑/↓ lands on the **edge line** of the neighboring part |
| Embed widgets + [`AppState`](../../../../core/app_state.dart) | Object **payload** (info body, tasks, …). Marker text stores pointer lines only |

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

After move, delete, or split, never leave an empty or whitespace/`\n`-only paragraph beside an embed (or stranded between text halves).

- Coalesce drops blank paragraph stubs (including those next to non-paragraphs).
- Split at a line boundary trims the line-break out of both halves so the origin does not keep a blank line.
- Backspace on an empty paragraph stub **removes the stub** even when the neighbor is an embed, list, or table.

Blank lines the user wants live as `\n` **inside** a paragraph — not as empty sibling blocks.

### 2. Edge landing

Approach from below → **end / last line** of what is above. Approach from above → **start / first line** of what is below.

Structural commits set `DocumentSessionResult.focusSegmentId` + `focusOffset` when the landing is not “first part at 0”. Hosts must not reset the caret to the start of an atomic embed when the flow already placed an end offset.

### 3. Object remount

The file owns placement; the object owns content. After drag or rebuild, object UI must keep or re-seed payload from the in-memory embed cache — never dispose a live info editor into a blank cache entry.

- Move Mode reorders the **pointer token** in marker text (cut/paste), not a live widget drag that remounts object editors.
- Move Mode keeps object editors **outside** `Draggable.child` / `childWhenDragging` when chrome is used.
- Info embeds use a `GlobalKey` and push controllers into `embedsByFileId` before structural rebuild.
- `updateInfoObject` patches the cache **before** the network round-trip.

## Checklist (regressions)

- Drag object mid-paragraph → no empty line at origin.
- Empty line above/below object → Backspace removes it.
- Delete object → caret at end of paragraph above.
- Caret below object, ↑ → end of object’s last line/part.
- Drag info with typed content → content still there after drop.
