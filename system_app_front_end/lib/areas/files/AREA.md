# Area: File structure & functionality (frontend)

Backend twin: [`system_app_back_end/areas/files/AREA.md`](../../../../system_app_back_end/areas/files/AREA.md) — read it for the storage format.

## Core rule

A file must feel like **one continuous piece of text**, the way a Word document does. Paragraphs, lists, and tables are part of the same flow, not separate widgets the user has to click into.

Everything the user writes is saved as a single v3 block tree in `files.document_json`. There is no plain-text mirror in the app.

## Structure

| Folder | Role |
|--------|------|
| [`model/`](model/) | Node types and JSON codec |
| [`editor/`](editor/) | The editor surface and block widgets |
| [`rich_text/`](rich_text/) | Span formatting, controllers, context menus |
| [`data/`](data/) | File and topic models + API services |

## Node types

| Node | JSON `type` | Widget |
|------|-------------|--------|
| Paragraph | `paragraph` | `FormattedTextField` — multiline, `\n` is a line break |
| Heading | `heading` | `FormattedTextField` in title style |
| Bullet list | `bullet_list` | `RichListEditor` |
| Ordered list | `ordered_list` | `RichListEditor` |
| Table | `table` | `RichTableEditor` |
| Embed | `embed` | Object widget — see [objects](../objects/AREA.md) |

Position is array order in `blocks[]`.

## Keeping the text fluent

| Context | Key | Behavior |
|---------|-----|----------|
| Paragraph | Enter | New line **in the same paragraph** — never splits the block |
| Paragraph | Backspace at start of empty block | Merge into the previous paragraph |
| List | Enter on a filled item | New list item, cursor moves to it |
| List | Enter on an empty item | Drop that item, keep the list, continue as a paragraph below |
| List | Backspace on an empty item | Remove the item, or exit the list if it was the last |
| Table | Enter | Move to the cell below; add a row when on the last row |
| Table | Enter on an empty row | Drop that row, keep the table, continue as a paragraph below |
| Table | Shift+Enter | Line break inside the cell |
| Table | Tab | Next cell |
| Table | Right-click | Add column |

The empty-line-exits rule is what makes lists and tables feel like part of the text: the user presses Enter twice and simply keeps writing, exactly as they would in a word processor.

Adjacent paragraphs are coalesced on load so a document that was split into many blocks reads as one body.

## Rich text

Inline bold, italic, underline, size, and color are **spans** — ranges over a node's `text`. Span invariants live in [`rich_text/RICH_TEXT.md`](rich_text/RICH_TEXT.md).

`SpanTextEditingController` keeps text and spans in sync; formatting actions operate on the current selection through `block_text_actions.dart`.

## How objects fit in

An embedded object is a block in the document with an `object_id`. The document decides **where** it sits; the [objects area](../objects/AREA.md) renders and edits **what it contains**.

Deleting an embed must go through the object service so the backing row is cleaned up.

## Text version vs full version

| Version | What it is | Who uses it |
|---------|------------|-------------|
| **Full** | Block tree with spans and embed ids | The editor, saved to `document_json` |
| **Text** | Flattened plain text with fenced regions | The AI agent, search, diffs |

The app only ever handles the full version. The text version is produced by the backend on demand and shown to the user only inside AI diff review.

## Saving

Edits mutate the in-memory tree, then serialize through `DocumentCodec.serialize` and `PATCH document_json`. Saves are debounced and silent — typing never triggers a full rebuild, or the cursor would jump.

Undo/redo is tracked by `document_edit_history.dart` at document level.

## Rules

- Enter never splits a paragraph into two blocks.
- Never store or display derived plain text in the app.
- Never rebuild the whole editor on a keystroke; save silently and keep focus.
- An empty list item or table row plus Enter exits that structure **without destroying it**.
- All formatting goes through spans, never through separate styled blocks.

## Not done yet

Selection still cannot cross block boundaries — the user cannot drag-select from a paragraph through a table. The target is a `DocumentSession` owning one selection, one clipboard, and one undo stack across the whole document, with block widgets becoming views over it.
