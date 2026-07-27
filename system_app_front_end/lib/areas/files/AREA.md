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
| List | Right-click | Switch the list between points and numbers |
| Table | Enter | Move to the cell below; add a row when on the last row |
| Table | Enter on an empty row | Drop that row, keep the table, continue as a paragraph below |
| Table | Shift+Enter | Line break inside the cell |
| Table | Tab | Next cell |
| Table | Right-click | Add column |

The empty-line-exits rule is what makes lists and tables feel like part of the text: the user presses Enter twice and simply keeps writing, exactly as they would in a word processor.

Adjacent paragraphs are coalesced on load so a document that was split into many blocks reads as one body.

A newly inserted list or table gets the caret in its first bullet or its top-left cell, so inserting one is the same gesture as starting a new paragraph — insert and type.

The insert bar offers **one** list button, not two. Points vs numbers is a property of a list that already exists, switched from its right-click menu, so the user chooses "a list" and then how it looks.

### A row and a bullet are each one line of text

This is the rule the rest of the cursor behavior follows from. **A bullet in a list and a row in a table count as one line of the document**, no different from a line of a paragraph. Anywhere a decision has to be made about the caret or a marking, resolve it by asking what would happen if the part were a plain line:

| Situation | Because a part is a line |
|-----------|--------------------------|
| Arrow up out of a bullet | Lands on the **last** line of whatever is above, not its first |
| Arrow down out of a bullet | Lands on the **first** line of whatever is below |
| Vertical movement | Keeps the caret's horizontal position, measured in pixels off the caret rect, so it holds through wrapping and mixed scripts |
| Marking a whole bullet or row and deleting | The bullet or row goes, the way deleting a marked line removes the line |
| Marking every bullet or every row | The list or table goes with them |

Anything that would make a part behave unlike a line — a caret that stalls at a boundary, a delete that leaves an empty bullet behind — is a bug in this area, not a detail of the widget.

### Deleting a part, not just its text

A marking that covers a part **end to end** removes the part; a marking that covers only some of its text just deletes the text. [`editor/document_structure_prune.dart`](editor/document_structure_prune.dart) is the single place that decides this, and it is a pure function over `blocks[]` so the rules are testable without the widget tree.

| Marked | Result |
|--------|--------|
| A whole bullet | The bullet is removed |
| Every bullet in a list | The list block is removed |
| Every cell of a row | The row is removed |
| Every row of a table | The table block is removed |
| A whole paragraph, as part of a larger marking | The paragraph is removed |
| A whole paragraph, marked on its own | Text cleared, the paragraph stays |
| Part of a bullet, row, or cell | Text only, nothing is removed |

The last two keep single-part editing predictable: clearing a line in a word processor leaves the line. A file always keeps at least one paragraph, so there is somewhere to type after deleting everything.

### Arrow keys in Hebrew

An arrow moves the caret **the way it points on screen**, in both languages. A Flutter text field moves the caret through the *string*, so in Hebrew the left arrow walks backwards on screen.

The fix reconfigures the editor rather than intercepting keys. A text field dispatches an *intent* for every caret movement; [`rich_text/rtl_caret_motion.dart`](rich_text/rtl_caret_motion.dart) overrides the horizontal ones and flips `forward`, then hands them back to the field's own action through `callingAction`. Flutter still performs the move.

**Do not reimplement caret movement in a key handler.** It was tried and it was worse in exactly the ways that are invisible in English: held-down arrows arrive as `KeyRepeatEvent` and silently fall back to the wrong direction, and driving each step through the document flow rebuilds every part of the file per keypress, which makes a held arrow crawl. Delegating keeps key repeat, shift-extension, grapheme clusters and per-platform bindings for free.

`FormattedTextField` wraps the field in these overrides **only** when the ambient `Directionality` is RTL; in LTR nothing is wrapped. The flow's own key handler still decides which *edge* of a part is the exit, and that edge is mirrored in RTL — the left arrow leaves from the logical end of the text.

## One cursor across the whole file

Each paragraph, each bullet, and each table cell is a separate `TextField` — but the user must never feel that. [`editor/document_text_flow.dart`](editor/document_text_flow.dart) puts every one of those **segments** in document order and owns the caret and selection *across* them.

| Concept | Meaning |
|---------|---------|
| Segment | One editable run: a paragraph, one bullet, or one cell |
| `DocumentTextPosition` | Caret as `(segmentId, offset)` rather than an offset in one field |
| `DocumentTextSelection` | Anchor and focus, each free to sit in a different segment |

Segment ids come from the document tree, so order is always derived from `blocks[]`, never from widget build order:

| Part | Id |
|------|-----|
| Paragraph / heading | `blockId` |
| List item | `blockId#i<index>` |
| Table cell | `blockId#c<row>:<col>` |

`BlockDocumentEditor` pushes the order on every build; the fields attach themselves through `DocumentTextFlowScope`.

### What it gives the user

| Action | Behavior |
|--------|----------|
| Left/Right at a part's edge | Caret crosses into the neighbouring part |
| Up/Down on the first/last line | Caret moves into the part above/below |
| Up/Down inside a table | Moves **by column**, and leaves the table from the edge rows |
| Shift+arrows | Selection grows past part boundaries |
| Shift+click, drag | Marks across paragraphs, bullets, and cells at once |
| Cmd+A | Selects the entire file, every part |
| Copy / cut | Joins the marked parts with newlines |
| Backspace / typing | Replaces the whole marked range |

Vertical movement is grid-aware because reading order and visual order differ in a table: the cell after `r0c0` is `r0c1`, but the cell *below* it is `r1c0`. `setVerticalLinks` carries that override.

A selection inside a single part is left to that text field's own painting. Only a selection that spans parts is drawn by the editor, over every part it touches, while the focused field keeps the caret.

## There is only one marking

**Rule:** every action — right-click menu, clipboard, formatting, and later AI — acts on **the mark**, and the mark is resolved by exactly one rule:

1. **If anything is marked, that is the target** — even when the marking runs across several paragraphs, bullets, or cells.
2. **If nothing is marked, the target is the line at the caret.**

There is no second kind of marking. A single field's `TextEditingController.selection` is an implementation detail of how that field paints; it must never be what an action reads to decide what to affect. Two selections would drift apart, and an action would hit text the user did not mark.

[`editor/document_mark.dart`](editor/document_mark.dart) owns this.

| Type | Role |
|------|------|
| `DocumentMark` | The resolved target: an ordered list of parts with a range in each |
| `MarkedSpan` | One part's share — its controller, range, and model-update callback |
| `DocumentMark.resolve` | Applies the rule above against a `DocumentTextFlow` |
| `DocumentMark.resolveForController` | Same rule for a lone field with no flow (e.g. a task title) |

Everything an action needs is on the mark, so no action re-derives ranges:

| Method | Used by |
|--------|---------|
| `text` | Copy, cut, and the text handed to AI |
| `delete()` | Cut, backspace, typing over a marking |
| `replaceWith()` | Paste, typing over a marking |
| `applyFormat()` | Bold, italic, underline, size, color |

### Freezing

Opening the right-click menu can move focus and collapse a selection, so the mark is captured on secondary pointer-down (`capturePendingMark`) and **frozen** for the life of the menu (`openMenuSession`). While a menu is open, `resolveMark()` returns the frozen mark, so the target cannot shift under the user between opening the menu and choosing an item.

The frozen mark is also what gets highlighted, on **every part it covers**, so the user can see the exact extent an action will apply to before choosing it.

Right-clicking *outside* an existing marking clears it first, so the action targets the line pointed at rather than a marking elsewhere in the file.

### Deliberate limits

- Deleting across parts removes the parts it emptied **in full** and clears the rest. The first and last part are not merged into one.
- Enter over a multi-part selection deletes it and stops; the split happens on a second press, at a caret that is unambiguously in one part.
- Embeds are not segments yet, so the caret jumps over them.

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
- Any new editable text must register a segment with the flow, or the caret will not reach it.
- Segment order comes from the document tree, never from widget build order.
- There is one marking. Every action resolves its target through `DocumentMark`, never from a single field's selection.
- With nothing marked, an action applies to the caret's line — never to nothing, and never to the whole part.
- A bullet and a row each count as one line of text; settle caret and marking questions by asking what a plain line would do.
- A part is removed only when it was marked end to end; a partial marking never destroys structure.
- An arrow key moves the caret the direction it points on screen, in Hebrew as in English.
- A list has one style. Points vs numbers is switched on the existing list, never offered as two kinds of list to insert.

## Not done yet

- Deleting across parts does not merge the first and last part into one.
- Cmd+arrow and Home/End still follow the platform's logical direction in Hebrew. They share one intent with Home/End, so flipping it would break those; plain and Alt+arrow are handled.
- Undo/redo is still per document mutation, not one stack shared with cross-part edits.
- Objects are not part of the flow; the caret cannot enter an embed.
