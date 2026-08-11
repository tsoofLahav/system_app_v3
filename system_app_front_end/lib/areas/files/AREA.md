# Area: File structure & functionality (frontend)

Backend twin: [`system_app_back_end/areas/files/AREA.md`](../../../../system_app_back_end/areas/files/AREA.md) — read it for the storage format.

## Core rule

A file must feel like **one continuous piece of text**, the way a Word document does. Paragraphs, lists, and tables are part of the same flow, not separate widgets the user has to click into.

Everything the user writes is saved as **marker text (v4)** in `files.document_json` (header `%%system_app_document v4`). Spec: [`editor/DOCUMENT_TEXT.md`](editor/DOCUMENT_TEXT.md).

**Runtime editing surface** = Super Editor ([`editor/super_document_editor.dart`](editor/super_document_editor.dart)). Marker ↔ `MutableDocument` via [`model/marker_super_editor_bridge.dart`](model/marker_super_editor_bridge.dart). Object payloads stay in the objects area (file holds pointer lines only).

## Structure

| Folder | Role |
|--------|------|
| [`editor/super_document_editor.dart`](editor/super_document_editor.dart) | File editor host (`SuperEditor` + save/insert/Move Mode) |
| [`editor/embed_move_bubble.dart`](editor/embed_move_bubble.dart) | Floating glass Move Mode controls (outside the file) |
| [`model/marker_super_editor_bridge.dart`](model/marker_super_editor_bridge.dart) | Marker text ↔ Super Editor document |
| [`model/object_embed_node.dart`](model/object_embed_node.dart) | Custom SE node for object pointers |
| [`model/document_text_codec.dart`](model/document_text_codec.dart) | Marker parse/serialize helpers |
| [`model/document_buffer.dart`](model/document_buffer.dart) | Marker-range helpers (tests / legacy ops) |
| [`editor/DOCUMENT_TEXT.md`](editor/DOCUMENT_TEXT.md) | Marker-text dialect (SoT vs agent expand) |
| [`editor/FLUENT_TEXT.md`](editor/FLUENT_TEXT.md) | Fluent-text principles for embeds |
| [`editor/embeds/`](editor/embeds/) | In-file presentation of objects (task list, info, image, graph, table) |
| [`editor/object_embed_component.dart`](editor/object_embed_component.dart) | SE `ComponentBuilder` wrapping embed UIs |
| [`rich_text/`](rich_text/) | Span formatting used inside embeds (tables, info, …) |
| [`rich_text/rtl/`](rich_text/rtl/RTL.md) | **RTL solution** — Hebrew/BiDi direction helpers |
| [`data/`](data/) | File and topic models + API services |

### Document vs Super Editor (one sync rule)

**Persisted SoT** = marker text (`%%system_app_document v4\n` + body). **Session SoT** = Super Editor `MutableDocument` (undo via SE history). Save = bridge serialize → debounced `PATCH document_json`. Embed node ids are stable (`embed:<objectId>`). Object **payloads** stay in the objects area.

### One scroll owner

Each file pane scrolls its document in a local `CustomScrollView` with `SuperEditor` as a **sliver** (`shrinkWrap: true`). The topic canvas also scrolls; SE always emits a sliver when any ancestor `Scrollable` exists, so it must never sit under `Column` / `Expanded` / box parents.

### Visual rules (Super Editor stylesheet)

| Rule | Value |
|------|--------|
| Content width | Full pane (`maxWidth: infinity`) — never the SE default 640px column |
| Horizontal inset | 0 inside the editor (note card already pads) |
| Gap between blocks | `AppSpacing.blockGap` (3) — Enter = new paragraph with that top gap |
| Selection | Opaque teal wash on note surface + span `backgroundColor` via [`selection_background_phase.dart`](editor/selection_background_phase.dart) (SE's beneath-layer highlight alone misses RTL/Hebrew) |
| Text align | `TextAlign.start` (follows paragraph direction — see [`rich_text/rtl/RTL.md`](rich_text/rtl/RTL.md)) |
| Right-click | `DocumentContextMenu` (bold/italic/cut/copy/paste; list style switch on list items) |

## Node types

| Marker / object | Super Editor | Widget |
|-----------------|--------------|--------|
| Paragraph / heading | `ParagraphNode` (+ heading metadata) | SE text components |
| Bullet / ordered list fence | N× `ListItemNode` | SE list components |
| Object pointer | `ObjectEmbedNode` ([`BlockNode`](model/object_embed_node.dart)) | [`editor/embeds/`](editor/embeds/) via [`object_embed_component.dart`](editor/object_embed_component.dart) |
| Table object (`[TABLE id]`) | `ObjectEmbedNode` type `table` | `RichTableEditor` via [`embeds/table_embed.dart`](editor/embeds/table_embed.dart) |

Legacy `[TABLE]…[/TABLE]` fences are migrated to table objects on open.

### Embeds vs document caret (SE rules)

**Line-chain model** — see [`FLUENT_TEXT.md`](editor/FLUENT_TEXT.md) § Embed line navigation:

- Every editable unit inside an embed is a line (info text, tasks, table/graph cells).
- ↑/↓ never leaves a collapsed caret on the embed block; images are skipped.
- [`DocumentCaretSession`](editor/document_caret_session.dart) owns document↔embed; gateways expose `lineCount` / `focusLine`.
- Shift-select can include the **whole** embed with surrounding text (atomic for document mark).

## Keeping the text fluent

Embeds-in-flow principles (empty neighbors, edge landing, object remount): **[`editor/FLUENT_TEXT.md`](editor/FLUENT_TEXT.md)**.

| Context | Key | Behavior |
|---------|-----|----------|
| Paragraph | Enter | New line **in the same paragraph** — never splits the block |
| Paragraph | Backspace at start of empty block | Remove the stub / merge into the previous paragraph (works next to embeds too) |
| List | Enter on a filled item | New list item, cursor moves to it |
| List | Enter on an empty item | Drop that item, keep the list, continue as a paragraph below |
| List | Backspace on an empty item | Remove the item, or exit the list if it was the last |
| List | Right-click | Switch the list between points and numbers |
| Table | Enter | Move to the cell below; add a row when on the last row |
| Table | Enter on an empty row | Drop that row, keep the table, continue as a paragraph below |
| Table | Backspace on an empty row | Remove the row; if it was the last row, remove the table |
| Table | Shift+Enter | Line break inside the cell |
| Table | Tab | Next cell |
| Table | ←/→ at text edge | Adjacent cell in the same row (physical grid; macOS intents + key events) |
| Table | ↑/↓ at first/last line | Cell above/below in the same column; leave embed at top/bottom |
| Table | Right-click | Add column |
| Table + chart | Enter | Next column (series); add a column on the last |
| Table + chart | Arrows | Same physical 2D grid as a normal table (not series-reading order) |

The empty-line-exits rule is what makes lists and tables feel like part of the text: the user presses Enter twice and simply keeps writing, exactly as they would in a word processor.

Adjacent paragraphs are coalesced on load so a document that was split into many blocks reads as one body.

A newly inserted list or table gets the caret in its first bullet or its top-left cell, so inserting one is the same gesture as starting a new paragraph — insert and type.

The insert bar offers **one** list button, not two. Points vs numbers is a property of a list that already exists, switched from its right-click menu, so the user chooses "a list" and then how it looks.

### A row, a bullet, and an embed are each one line of text

This is the rule the rest of the cursor behavior follows from. **A bullet, a table row, and an embed (or each of its editable parts) count as one line of the document**, no different from a line of a paragraph. Anywhere a decision has to be made about the caret or a marking, resolve it by asking what would happen if the part were a plain line — details in [`editor/FLUENT_TEXT.md`](editor/FLUENT_TEXT.md):

| Situation | Because a part is a line |
|-----------|--------------------------|
| Arrow up out of a bullet / into an object | Lands on the **last** line of whatever is above, not its first |
| Arrow down out of a bullet / out of an object | Lands on the **first** line of whatever is below |
| Delete an object | Caret at the **end** of the text that was above it |
| Vertical movement | Keeps the caret's horizontal position, measured in pixels off the caret rect, so it holds through wrapping and mixed scripts |
| Marking a whole bullet, row, or object and deleting | That part goes, the way deleting a marked line removes the line |
| Marking every bullet or every row | The list or table goes with them |

Anything that would make a part behave unlike a line — a caret that stalls at a boundary, a delete that leaves an empty bullet or blank gap behind — is a bug in this area, not a detail of the widget.

### Deleting a part, not just its text

A marking that covers a part **end to end** removes the part; a marking that covers only some of its text just deletes the text. The same applies when the user selects **all** of a structure part and presses Backspace/Delete/Cut — lists, tables, and objects should disappear like lines of text, not leave empty shells. [`editor/document_structure_prune.dart`](editor/document_structure_prune.dart) is the single place that decides this (pure over `blocks[]`).

| Marked / cleared | Result |
|------------------|--------|
| A whole bullet (mark or select-all + delete) | The bullet is removed |
| Every bullet / last bullet deleted | The list block is removed |
| Every cell of a row | The row is removed |
| Every cell of a table | The table block is removed |
| Whole atomic embed, or info text cleared | The object is removed (and its backing row) |
| All tasks in a task list | The task-list object is removed |
| A whole paragraph, as part of a larger marking | The paragraph is removed |
| A whole paragraph, marked on its own | Text cleared, the paragraph stays |
| Part of a bullet, row, or cell | Text only, nothing is removed |

Empty **Enter** still exits below a list/table/object without destroying it (continue writing). Empty **Backspace** on the last unit removes the structure — empty list, empty table / row, or empty **object** (info / last task / last graph column) — then coalesces surrounding paragraphs (and resets text controllers so merged text is not lost). A file always keeps at least one paragraph.

### RTL / Hebrew

Fluent RTL (visual arrows, paragraph base direction, empty-padding taps, mixed Hebrew+English) lives in one place: **[`rich_text/rtl/RTL.md`](rich_text/rtl/RTL.md)** — embeds via `FormattedTextField`, file body via ambient-aware SE builders + visual ←/→ plugin. Do not add competing caret math outside that folder.

## One cursor across the whole file

Each paragraph, each bullet, and each table cell is a separate `TextField` — but the user must never feel that. [`editor/document_text_flow.dart`](editor/document_text_flow.dart) puts every one of those **segments** in document order and owns the caret and selection *across* them.

| Concept | Meaning |
|---------|---------|
| Segment | One editable run: a paragraph, one bullet, or one cell |
| `DocumentTextPosition` | Caret as `(segmentId, offset)` rather than an offset in one field |
| `DocumentTextSelection` | Anchor and focus, each free to sit in a different segment |

Segment ids come from buffer parts (view = `blocks[]`), never from widget build order:

| Part | Id |
|------|-----|
| Paragraph / heading | `blockId` |
| List item | `blockId#i<index>` |
| Table cell | `blockId#c<row>:<col>` |
| Embed (whole object) | `blockId#embed` |

Embed-internal fields may still register with `DocumentTextFlow` when nested; the file body itself is owned by Super Editor.

### What it gives the user

| Action | Behavior |
|--------|----------|
| Left/Right at a part's edge | Caret crosses into the neighbouring part |
| Up/Down on the first/last line | Caret moves into the part above/below |
| Up/Down inside a table | Moves **by column**, and leaves the table from the edge rows |
| Shift+arrows | Selection grows past part boundaries |
| Shift+click, drag | Marks across paragraphs, bullets, and cells at once |
| Click in empty space below / between parts | Structure: caret at the **logical end** of the last part above. Empty files fill the viewport so that area is tappable. (In-field empty padding → [RTL solution](rich_text/rtl/RTL.md).) |
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

The frozen mark is also what gets highlighted, on **every part it covers**, so the user can see the exact extent an action will apply to before choosing it. While that overlay is up, the field's native selection paint is hidden — there is never a second wash (user selection + line-at-caret) at the same time.

Right-clicking *outside* an existing marking clears it first, so the action targets the line pointed at rather than a marking elsewhere in the file.

### Deliberate limits

- Deleting across parts removes the parts it emptied **in full** and clears the rest. The first and last part are not merged into one.
- Enter over a multi-part selection deletes it and stops; the split happens on a second press, at a caret that is unambiguously in one part.

## Rich text

Inline bold, italic, underline, size, and color are **spans** — ranges over a node's `text`. Span invariants live in [`rich_text/RICH_TEXT.md`](rich_text/RICH_TEXT.md).

`SpanTextEditingController` keeps text and spans in sync; formatting actions operate on the current selection through `block_text_actions.dart`.

## How objects fit in (presentation)

An embedded object is a top-level block with an `object_id`. **This area** owns where it sits, how it joins the caret/mark, menus, frames, and Move Mode. **[Objects](../objects/AREA.md)** owns the backing data and special qualities (task **views**, info **links**, payloads).

Embed widgets live here and call into objects through a **thin overlay** (models/services + controls for object fields, e.g. the done toggle). Task done/active is **`tasks.status` in objects**, not a files-only UI detail. Embeds must not grow into the home of views logic or the link graph.

| Embed | Widget | Flow role |
|-------|--------|-----------|
| Task list | [`embeds/inline_task_list.dart`](editor/embeds/inline_task_list.dart) | Thin host: document segments + Move Mode; rows via objects [`TaskListSurface`](../objects/tasks/task_list_surface.dart) |
| Info | [`embeds/object_embed_widgets.dart`](editor/embeds/object_embed_widgets.dart) | One text field (first line = title); tag chips; right-click → text + **Add tag** / **Add connection** (field or block caret) |
| Image | same | Atomic unit; caption field |
| Table (+ chart) | [`embeds/table_embed.dart`](editor/embeds/table_embed.dart) | `RichTableEditor`; chart quality paints above the same grid |
| Host | [`embed_block_host.dart`](editor/embed_block_host.dart) | Move Mode; optional atomic `#embed` segment |
| Drag chrome | [`drag_mode_frame.dart`](editor/drag_mode_frame.dart) | Shared gentle glass frame for Move / Reorder modes |

### Placement rules

| Rule | Meaning |
|------|---------|
| Between blocks only | Never inside a list item or table cell |
| Create at the caret | Inserts go to the **last-claimed** file. Mid-paragraph / mid-heading **splits** at the caret (`before \| new \| after`); caret at the start inserts before that block; at the end, after it. List / table / embed carets insert after the containing block. |
| Marker buffer is source of truth | Position is top-level parts in buffer text (view = `blocks[]`); the object row holds data, not placement |
| Right-click on embed text | Same text menu as paragraphs (`DocumentMark`). Text colour opens the shared spectrum picker ([`../ui/color_dialog.dart`](../ui/color_dialog.dart)), not a fixed palette. Graphs extend the table cell menu (add column + chart options). Task lists add **Add to view…** and **Reorder tasks** |
| Move Mode | Double-click → glass frame on the object + floating glass bubble ([`embed_move_bubble.dart`](editor/embed_move_bubble.dart), no scrim; drag to reposition). Up/down in the bubble nudge the object and **stay in Move Mode**; Done or tap outside the bubble ends it. After move/delete, adjacent paragraphs **coalesce** (blank/`\n`-only stubs dropped, including next to embeds). |
| Empty object + Backspace | Same fluent rule as an empty list bullet / table row: last empty unit + Backspace **removes the object** (cascade-delete). |
| Object block + Tab | Opens the object (first inner field). **Escape** lands **after** the object so typing continues below. **Enter** inserts a paragraph below. Arrows do not auto-enter/leave objects. |
| Task Reorder Mode | Owned by `TaskListSurface` (objects): right-click → Reorder tasks → glass per task; **tap outside the list** ends it |

### Segment id

| Part | Id |
|------|-----|
| Atomic embed (image, or host when `registerAsUnit`) | `blockId#embed` via `embedSegmentId` |
| Task / info / graph parts | Per-part ids from `document_text_flow.dart` helpers |

Deleting a fully marked embed removes the block **and** cascades through the object service.

### Object enter / exit

Objects are atomic SE blocks. ↑/↓ move onto the block; **Tab** (or click) opens it; **Escape** places the caret after the object; **Enter** inserts a line below. Inner ↑/↓ stay inside (see [`editor/FLUENT_TEXT.md`](editor/FLUENT_TEXT.md)). Insert bar and **Insert object** shortcuts create an object then put the caret in its first field without a shell-wide notify (so Hebrew/Latin IME keeps working).

### In-file behaviour by type (presentation only)

| Type | In the document |
|------|-----------------|
| Task list | Active then Done; Enter adds in the same zone; Escape leaves to SE block; right-click → **Choose view…** / **Reorder tasks** (also on block caret); empty title + hint |
| Info | One field; first line = title (diagrams/API `title`); Enter adds lines; Escape leaves to SE block; right-click → text + Add tag / Add connection |
| Table | Grid; Enter adds rows; ←/→/↑/↓ move on the physical grid; menu adds columns; Escape leaves to SE block |
| Table + chart | Same embed; chart on top; fixed 2 rows; Enter adds columns (max **8**); arrows match the physical grid (same as table); insert template labels **A/B** or **א/ב** from UI language; right-click chart **or** cell → type + palette ([`AppColorPalettes`](../ui/app_color_palettes.dart)); pointer `[GRAPH id]` |
| Image | Display + caption; resize handles deferred |

Type logic beyond presentation (views, links, cascades) → [objects](../objects/AREA.md).

## Editor text vs agent text

| Layer | What it is | Who uses it |
|-------|------------|-------------|
| **Editor text (SoT)** | v4 marker body + header; pointer-only embeds | DB, Super Editor bridge, move/cut/paste |
| **Agent text** | Same structure with objects expanded to fences | Production agent tools, diffs |

The app edits and persists **editor text**. Agent text is produced on demand and shown in AI diff review only. Spec: [`editor/DOCUMENT_TEXT.md`](editor/DOCUMENT_TEXT.md).

## Saving

Edits mutate the Super Editor document; save serializes via the marker bridge and `PATCH document_json` (`%%system_app_document v4\n` + body). Saves are debounced and silent — typing never triggers a full editor remount from `AppState`.

In-session undo/redo uses Super Editor’s history stack.

## Keyboard / focus safety (recurring bug class)

Symptom: `KeyDownEvent … physical key is already pressed` (often loops on one letter). Cause: remounting Super Editor or disposing embed `FocusNode`s / `TextField`s while a key is still down.

**Coding-agent checklist (canonical):** [`DEVELOPMENT.md` § Editor keyboard safety](../../../../../DEVELOPMENT.md#editor-keyboard-safety-read-before-editing-the-file-editor).

In this area specifically:

| Do | Don't |
|----|--------|
| `updateFile` / `updateObjectPayload` / task+info title saves with `notify: false` | `ListenableBuilder` on `AppState` around `DocumentEditor` |
| Debounce embed PATCHes; patch cache **before** `await` | PATCH + `notifyListeners` / full embed reload on every `onChanged` |
| Super Editor `setState` only when embed **id/type/order** changes; defer with `runAfterKeystroke` if keys are down | Treat every new embeds-list identity as a reason to remount |
| Keep controllers as SoT while focused; skip `didUpdateWidget` resync if focused or keys down | Dispose cell/task/info focus nodes mid-KeyDown |
| Tab/Escape → `runNextFrame`; empty-structure Backspace → `runAfterKeystroke` | Sync `unfocus` / delete structure on the KeyDown frame |
| Remount `SuperEditor` (`ValueKey` epoch) when replacing `Editor` after silent reload | Swap `Editor` in place and keep a stale `DocumentImeInputClient` (Escape IME crash) |

Smoke after edits: type fast in paragraph + info + task + table/chart cell; Tab into object, type, Escape, keep typing.

## Rules

- Never store agent-expanded text in `document_json`; SoT is marker/pointer editor text.
- Never rebuild the whole editor on a keystroke; save silently and keep focus. Follow [Keyboard / focus safety](#keyboard--focus-safety-recurring-bug-class).
- An empty list item, table row, or trailing object unit (empty final task / info line / graph column) plus Enter exits that structure **without destroying it**.
- An empty object (empty info, last empty task, last empty graph column) plus Backspace **removes the object** and coalesces surrounding text — no leftover blank paragraph.
- Embed node ids are stable (`embed:<objectId>`); do not remount embeds under regenerated `p0`/`p1` keys.
- A bullet, a row, and an embed each count as one line of text; settle caret and marking questions by asking what a plain line would do ([`editor/FLUENT_TEXT.md`](editor/FLUENT_TEXT.md)).
- Never leave empty/`\n`-only paragraph neighbors after move/delete/split (bridge save prunes them).
- RTL / Hebrew caret and direction policy: only via [`rich_text/rtl/`](rich_text/rtl/RTL.md).
- A list has one style. Points vs numbers is switched on the existing list, never offered as two kinds of list to insert.

## Not done yet

- Deleting across parts does not merge the first and last part into one.
- Cmd+arrow and Home/End in Hebrew — see known gap in [`rich_text/rtl/RTL.md`](rich_text/rtl/RTL.md).
- Undo/redo is still per document mutation, not one stack shared with cross-part edits.
- Image resize handles deferred. Convert selection → Info is an objects-area product flow (uses object APIs) with a small files entry point.
