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
| [`editor/super_editor_mark.dart`](editor/super_editor_mark.dart) | Super Editor twin of `DocumentMark`: marked span, else caret line |
| [`editor/file_editor_keyboard_actions.dart`](editor/file_editor_keyboard_actions.dart) | Super Editor IME keys minus Cmd+B / Cmd+I (catalog owns those) |
| [`editor/cmd_click_link_handler.dart`](editor/cmd_click_link_handler.dart) | ⌘-click (Ctrl-click) opens a persisted web link |
| [`editor/edit_conflict.dart`](editor/edit_conflict.dart) | User vs agent: take inbound unless dirty, then ask |
| [`editor/embed_move_bubble.dart`](editor/embed_move_bubble.dart) | Floating glass Move Mode controls (outside the file) |
| [`model/marker_super_editor_bridge.dart`](model/marker_super_editor_bridge.dart) | Marker text ↔ Super Editor document |
| [`model/object_embed_node.dart`](model/object_embed_node.dart) | Custom SE node for object pointers |
| [`model/document_text_codec.dart`](model/document_text_codec.dart) | Marker parse/serialize helpers |
| [`model/document_buffer.dart`](model/document_buffer.dart) | Marker-range helpers (tests / legacy ops) |
| [`model/agent_text_blocks.dart`](model/agent_text_blocks.dart) | Agent text → display blocks, each keyed to its line |
| [`editor/read_only_document_view.dart`](editor/read_only_document_view.dart) | Paints those blocks (headings, lists, embeds) with no editing |
| [`editor/file_preview.dart`](editor/file_preview.dart) | Shared read-only file: agent text in, visual document out. Used by the AI diff, archive, arrange overlay, and bring-file cards |
| [`editor/DOCUMENT_TEXT.md`](editor/DOCUMENT_TEXT.md) | Marker-text dialect (SoT vs agent expand) |
| [`editor/FLUENT_TEXT.md`](editor/FLUENT_TEXT.md) | Fluent-text principles for embeds |
| [`editor/embeds/`](editor/embeds/) | In-file presentation of objects (task list, info, image, graph, table) |
| [`editor/object_embed_component.dart`](editor/object_embed_component.dart) | SE `ComponentBuilder` wrapping embed UIs |
| [`rich_text/`](rich_text/) | Span formatting used inside embeds (tables, info, …) |
| [`rich_text/rtl/`](rich_text/rtl/RTL.md) | **RTL solution** — Hebrew/BiDi direction helpers |
| [`data/`](data/) | File, topic, and topic-type models + API services. `files.meta.template_slot` is the stable key automations use |

A type's template is `template_topic_id` on that type. Set it from Preferences or by right-clicking a topic of that type. In Manage types, **Reorder** shows drag handles so sidebar sections can move. New topics copy structure only (backend). **Duplicate** copies the topic in full (live files, object content, in-topic links, tags, icon, colour). Creating a type asks for an English name and a Hebrew name; the sidebar follows the app language.

### Document vs Super Editor (one sync rule)

**Persisted SoT** = marker text (`%%system_app_document v4\n` + body). **Session SoT** = Super Editor `MutableDocument` (undo via SE history). Save = bridge serialize → debounced `PATCH document_json`. Embed node ids are stable (`embed:<objectId>`). Object **payloads** stay in the objects area.

**One marking.** Super Editor body actions (right-click, format, cut/copy, Make link, AI `selected_text`) use the same rule as embed fields: if anything is marked, use that span; if not, use the **line at the caret**. [`caretLineSelection`](editor/super_editor_mark.dart) expands a collapsed caret before those actions. Object blocks stay whole-object (chrome menu), not a text line. Catalog **⌘B / ⌘I / ⌘U** toggle once — Super Editor’s own Cmd+B / Cmd+I are stripped so they cannot double-toggle.

**Web links.** Right-click **Make link** (no shortcut; ⌘K is bring-file) finds `http(s)://` or `www.` in the mark-or-caret-line and paints it like a description link. v4 still has no general span encoding; **links only** round-trip as CommonMark `[text](url)` in paragraph/list lines. ⌘-click (Ctrl-click) opens the URL. Object-field links store `link` on existing payload spans.

### The name in the header

The header of a pane ([`editor/document_pane.dart`](editor/document_pane.dart)) is a plain text field, so a rename ends the way the user ends it: **leaving the field saves** (focus loss, and the pane going away), not only Enter. Two rules keep it honest:

- Compare the typed text against the name **as shown**, not as stored. Built-in files are displayed translated (`Daily` reads `יומי`), so comparing against the stored name would rename a file to its own translation the first time focus passed through.
- A rename arriving from elsewhere (agent, reload) refreshes the field only while it is not focused — never on top of what is being typed.

A pane with `isBrought` is a file **visiting Home** from another topic (UX bring-file). It occupies a layout slot like any other file and can be rearranged with them. Edits save to that file; the ⋯ menu can dismiss that visit without archiving or deleting it. `showFileMenu: false` hides that menu for throwaway hosts (the fill-file snippet dialog).

The user never sees marker/editor text. Every read-only surface uses the same preview: `GET /files/:id/agent-text` (or already-expanded agent text) → `parseAgentTextBlocks` → [`FilePreview`](editor/file_preview.dart) → [`ReadOnlyDocumentView`](editor/read_only_document_view.dart). That is the AI diff, archive spotlight, arrange overlay cards, and bring-file cards. None of them mount `SuperDocumentEditor`, and none of them paint `document_json`. The archive list itself never downloads `document_json`; cards use id, name, and `archived_at`.

On phone the framed pane ends above the tool bubbles on the light-grey middle; the card keeps its shadow for depth. The bubbles have no lift shadow. Screen structure is locked in UX [`AREA.md` § Phone screen structure](../ux/AREA.md#phone-screen-structure).

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

Embeds-in-flow principles (blank lines as text, edge landing, object remount): **[`editor/FLUENT_TEXT.md`](editor/FLUENT_TEXT.md)**.

| Context | Key | Behavior |
|---------|-----|----------|
| Paragraph | Enter | New line **in the same paragraph** — never splits the block |
| Paragraph | Backspace at start of empty block | Remove the stub / merge into the previous paragraph (works next to embeds too) |
| List | Enter on a filled item | New list item, cursor moves to it |
| List | Enter on an empty item | Drop that item, keep the list, continue as a paragraph below |
| List | Backspace on an empty item | Remove the item, or exit the list if it was the last |
| List | Right-click | Switch the list between points and numbers |
| Table / chart | (keys) | See **[Tables & charts](#tables--charts)** below |

The empty-line-exits rule is what makes lists and tables feel like part of the text: the user presses Enter twice and simply keeps writing, exactly as they would in a word processor.

Adjacent paragraphs are coalesced on load so a document that was split into many blocks reads as one body.

A newly inserted list or table gets the caret in its first bullet or its top-left cell, so inserting one is the same gesture as starting a new paragraph — insert and type.

The insert bar offers **one** list button, not two. Points vs numbers is a property of a list that already exists, switched from its right-click menu, so the user chooses "a list" and then how it looks.

It offers no paragraph button either: the file is free text, so a plain line is always one keystroke away. The bar is only for what typing cannot make — a list, and the objects.

Insertion goes where the caret is, blank lines included: press Enter a few times and the object lands in the gap, not back up under the last paragraph. That holds because the save keeps those empty lines ([`editor/FLUENT_TEXT.md`](editor/FLUENT_TEXT.md) § A blank line is text).

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

### And one cursor across open files

A topic shows several files at once, so several Super Editors are mounted at once, and each one is a text input of its own. Two rules keep that from reading as two cursors:

| Rule | Why |
|------|-----|
| Every editor gets `inputRole: 'file-<id>'` | The IME connection is global and shared. Without a role the second file registers as the same input, the two panes fight over the connection, and in debug super_editor throws *duplicate input IDs*. |
| Only the file that is claimed **and** has primary focus draws a caret (`documentOverlayBuilders`) | A pane keeps its selection when it loses focus — the marking is what actions run on — so the caret is the only thing left to hide (including tap-outside, which closes the keyboard). Text shortcuts Super Editor does not handle itself (underline, size) go through `applyTextAction` on that claimed controller. |

Hiding it means swapping Super Editor's cursor layers (desktop caret + the iOS / Android handle layers) for an empty layer of the same count. Two things that look simpler do not work: **removing** a layer leaves it painting, because `ContentLayers` matches overlays by index and never deactivates one past the end of a shorter list; **styling** the caret away fails too, because the blink controller writes its own alpha over the colour, so a transparent caret comes back opaque black.

Claim still follows the click (inserts and AI keep a target file). The caret itself follows primary focus, so tap-outside, a dialog, or another field hides it.

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
| Info | [`embeds/object_embed_widgets.dart`](editor/embeds/object_embed_widgets.dart) | One text field (first line = title); tag chips; **field** right-click → formatting + **Connect info…**; **chrome** (block caret) → Add tag / Add connection (related) |
| Image | same | Atomic unit; caption field |
| Table (+ chart) | [`embeds/table_embed.dart`](editor/embeds/table_embed.dart) | `RichTableEditor` + optional chart; behaviour in **[Tables & charts](#tables--charts)** |
| Host | [`embed_block_host.dart`](editor/embed_block_host.dart) | Move Mode; optional atomic `#embed` segment |
| Drag chrome | [`drag_mode_frame.dart`](editor/drag_mode_frame.dart) | Shared gentle glass frame for Move / Reorder modes |

### Placement rules

| Rule | Meaning |
|------|---------|
| Between blocks only | Never inside a list item or table cell |
| Create at the caret | Inserts go to the **last-claimed** file. Mid-paragraph / mid-heading **splits** at the caret (`before \| new \| after`); caret at the start inserts before that block; at the end, after it. List / table / embed carets insert after the containing block. |
| Marker buffer is source of truth | Position is top-level parts in buffer text (view = `blocks[]`); the object row holds data, not placement |
| Right-click on embed text | Same text menu as paragraphs (`DocumentMark`) plus **Connect info…** on object fields (info / task / table) and **Make link**. Connected spans and URL `link` spans paint in `AppColors.descriptionLink` (dark teal glyphs + 1px underline). Description-link colour is paint-only; URL `link` is stored on the field span. Text colour opens the shared spectrum picker ([`../ui/color_dialog.dart`](../ui/color_dialog.dart)), not a fixed palette. Tables/charts: see **[Tables & charts](#tables--charts)**. Task lists add **Add to view…** and **Reorder tasks**. Info **chrome** (not a field) is Add tag / Add connection / **Move object**. Super Editor body paragraphs do not offer Connect info. |
| Move Mode | Object chrome menu **Move object**, or **⌘⇧O** when the caret / last-interacted embed is an object → glass frame on the object + floating glass bubble ([`embed_move_bubble.dart`](editor/embed_move_bubble.dart), no scrim; drag to reposition). Double-click selects a word in inner fields, like body text. Up/down in the bubble nudge the object and **stay in Move Mode**; Done or tap outside the bubble ends it. After move/delete, adjacent paragraphs **coalesce** (blank/`\n`-only stubs dropped, including next to embeds). |
| Empty object + Backspace | Same fluent rule as an empty list bullet / table row: last empty unit + Backspace **removes the object** (cascade-delete). |
| Object block + Shift+Enter | Opens the object (first inner field). **Shift+Enter** inside lands **after** the object so typing continues below. On phone, those keys are not on the keyboard — the first bottom-bar pill is arrows plus enter/leave. **Enter** inserts a paragraph below. Arrows do not auto-enter/leave objects. Phone long-press / secondary tap opens the object chrome menu (Move Mode lives there). |
| Task Reorder Mode | Owned by `TaskListSurface` (objects): right-click → Reorder tasks → glass per task; **tap outside the list** ends it |

### Segment id

| Part | Id |
|------|-----|
| Atomic embed (image, or host when `registerAsUnit`) | `blockId#embed` via `embedSegmentId` |
| Task / info / graph parts | Per-part ids from `document_text_flow.dart` helpers |

Deleting an embed (empty Backspace, or selecting the block / cutting it out of the file) removes the pointer **and** cascade-deletes the object row. File `PATCH` also purges any `objects` rows for that file whose pointers are gone from `document_json`, so the objects map cannot keep showing orphans.

### Object enter / exit

Objects are atomic SE blocks. ↑/↓ move onto the block; **Shift+Enter** (or click) opens it; **Shift+Enter** again places the caret after the object; **Enter** inserts a line below. On phone the first bottom-bar pill is **arrows + enter/leave** (no Shift+Enter key). Arrows inside an object stay inside; on the block they move to the next/previous block. Inside an object, phone Return and empty delete are the same structure keys as desktop Enter / empty Backspace (`FormattedTextField` maps the IME — iOS will not send those as `KeyEvent`s). Insert, delete, and add-part must keep the writing session (no Super Editor remount on payload refresh). Insert bar and **Insert object** shortcuts create an object then put the caret in its first field without a shell-wide notify (so Hebrew/Latin IME keeps working).

### In-file behaviour by type (presentation only)

| Type | In the document |
|------|-----------------|
| Task list | Active then Done; Enter adds in the same zone; **insert lands on the list header** (then tasks); Shift+Enter leaves to SE block; right-click → **Choose view…** / **Reorder tasks** (also on block caret); empty title stays blank |
| Info | One field; first line = title (diagrams/API `title`, not announced in the UI); Enter adds lines; Shift+Enter leaves to SE block; field right-click → text + Connect info; chrome → Add tag / Add connection (⌘L while in the info; otherwise ⌘L inserts a list) |
| Table / chart | See **[Tables & charts](#tables--charts)** |
| Image | Display + caption; right-click **Make smaller / larger** (steps of 10% of the pane) or **Tiny / Quarter / Half / Full size**. Width is `payload.width` 0–1 of the file pane; aspect ratio stays (`BoxFit.contain`) |

### Tables & charts

One object type `table` (`payload.rows` + optional `payload.chart`). UI: [`table_embed.dart`](editor/embeds/table_embed.dart) + [`RichTableEditor`](rich_text/rich_table_editor.dart); reorder chrome in [`table_reorder_surface.dart`](rich_text/table_reorder_surface.dart). `[GRAPH id]` is sugar for chart-on. Insert starts with empty cells — no placeholder labels.

| | Plain table | Chart table |
|--|-------------|-------------|
| Shape | N×M grid | Fixed 2 rows (labels / values); max **8** columns |
| Enter | Cell below; add row on last filled row | Next column; add column on last |
| Empty Enter | Drop that row; keep table; continue below | (column exit path) |
| Empty Backspace | Empty cell → previous cell (reading order, land at end). First cell of an **empty row** removes that row; last empty row removes the table | Empty cell → previous cell; empty column still removes the column; last removes object |
| Phone | Same Enter / empty Backspace, via the IME map in `FormattedTextField` (no hardware keys). Moving between cells/tasks keeps the keyboard up (no unfocus gap). Arrow pad order: left, down, up, right — pad icons never mirror. The typing session never remounts a cell on IME language switch or clearing one cell | Same |
| Arrows | One owner: [`table_grid_nav.dart`](rich_text/table_grid_nav.dart). Physical ←/→ (pad and hardware) move to the cell that is visually left/right. Hebrew **UI** paints col 0 on the right, so physical left is a higher column. In-cell caret is first-strong (`rtl/`), not grid RTL. Landing is the **visual** edge entered from: visual-right of an RTL cell is logical start. From below → end; from above → start. Phone edges stay inside the table | Same grid rules |
| Tab | Next cell | Same |
| Shift+Enter | Leave to SE block caret | Same |
| Add row / column | **Immediately after the right-clicked cell** (storage index + 1; in RTL that is visually left of the cell). Anchor is the click, not a drifting “end” | Add **column** only (same anchor rule) |
| Reorder | Separate **Reorder rows…** / **Reorder columns…**; grab the glass row/column (no handles) | **Reorder columns…** only; series colors move with the column |
| Exit reorder | Tap outside / Escape / Done | Same |
| Right-click | Text + Connect info + add/reorder; block caret is add/reorder only | Chart chrome **or** cell → type + palette ([`AppColorPalettes`](../ui/app_color_palettes.dart)); columns reorder; cells still get Connect info |

Type logic beyond presentation (views, links, cascades) → [objects](../objects/AREA.md).

## Editor text vs agent text

| Layer | What it is | Who uses it |
|-------|------------|-------------|
| **Editor text (SoT)** | v4 marker body + header; pointer-only embeds | DB, Super Editor bridge, move/cut/paste |
| **Agent text** | Same structure with objects expanded to fences | Production agent tools, diffs |

The app edits and persists **editor text**. Agent text is produced on demand. The user sees it only as a visual document through [`FilePreview`](editor/file_preview.dart) — never as raw fences or `%%system_app_document` headers. Spec: [`editor/DOCUMENT_TEXT.md`](editor/DOCUMENT_TEXT.md).

Agent text is parsed twice: [`document_agent_text.py`](../../../../system_app_back_end/areas/files/services/document_agent_text.py) writes, [`model/agent_text_blocks.dart`](model/agent_text_blocks.dart) only displays. The Python side leads — when the fence format changes, change it there first and follow here, or the review dialog shows markers again.

The display side is deliberately forgiving where the write side is strict: item lines with no fence around them are drawn as a list, and a leftover marker is drawn as a quiet rule. Marker language must never reach the reader, even when the text is malformed.

## Saving

Edits mutate the Super Editor document; save serializes via the marker bridge and `PATCH document_json` (`%%system_app_document v4\n` + body). Saves are debounced and silent — typing never triggers a full editor remount from `AppState`.

A newer body from elsewhere (phone, agent) is applied **into** the already-open `SuperDocumentEditor`. The topic page is not rebuilt for that. Who listens where: UX [`AREA.md` § Who rebuilds](../ux/AREA.md#who-rebuilds).

**User vs agent:** if the open file has no unsaved local edits (paragraphs or embeds), take the inbound copy. If both sides changed, ask which version to keep ([`edit_conflict.dart`](editor/edit_conflict.dart)) — never silently write a stale local payload over an agent graph on dispose. Keyboard safety still applies: wait until no key is down before remounting cells or showing the dialog.

In-session undo/redo uses Super Editor’s history stack.

## Keyboard / focus safety (recurring bug class)

Symptom: `KeyDownEvent … physical key is already pressed` (often loops on one letter). Cause: remounting Super Editor or disposing embed `FocusNode`s / `TextField`s while a key is still down.

**Coding-agent checklist (canonical):** [`NOTES.md` § Editor keyboard safety](../../../../../NOTES.md#editor-keyboard-safety).

In this area specifically:

| Do | Don't |
|----|--------|
| Keep the open editor mounted; apply remote body/embed updates into it | Rebuild `MaterialApp` or the topic canvas on every `AppState` notify; wrap `DocumentEditor` in `ListenableBuilder(listenable: appState)` |
| `updateFile` / `updateObjectPayload` / task+info title saves with `notify: false` | `notifyListeners` from a keystroke / `onChanged` path |
| Debounce embed PATCHes; patch cache **before** `await` | PATCH + `notifyListeners` / full embed reload on every `onChanged` |
| Super Editor `setState` only when embed **id/type/order** changes; defer with `runAfterKeystroke` if keys are down. Phone IME has no keys-down — payload refresh must not remount | Treat every new embeds-list identity as a reason to remount; remount a `TextField` after the first letter |
| Keep controllers as SoT while **dirty**; take inbound when not dirty (after keys are up). If both dirty, ask. Dispose must not PATCH a payload that is older than the cache | Overwrite live cells from a stale cache while typing; flush old graph/info on dispose over an agent write; dispose cell/task/info focus nodes mid-KeyDown |
| Shift+Enter → `runNextFrame`; empty-structure Backspace → `runAfterKeystroke` | Sync `unfocus` / delete structure on the KeyDown frame |
| Tap outside the focused editor (canvas / empty padding) unfocuses and closes the keyboard. Bottom menus and the open object do not. | Leave Super Editor focused when the tap is not on another field |
| Remount `SuperEditor` (`ValueKey` epoch) when replacing `Editor` after silent reload | Swap `Editor` in place and keep a stale `DocumentImeInputClient` (Escape IME crash) |

Smoke after edits: type fast in paragraph + info + task + table/chart cell; Shift+Enter into object, type, Shift+Enter out, keep typing.

## Rules

- Never store agent-expanded text in `document_json`; SoT is marker/pointer editor text.
- Never show marker/editor text to the user. Read-only surfaces go through [`FilePreview`](editor/file_preview.dart).
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
- Convert selection → Info is an objects-area product flow (uses object APIs) with a small files entry point.
