# Area: UX — flow and experience

**What happens, and where things live.** Not how they are painted — that is [UI](../ui/AREA.md).

Backend twin: none. This area is frontend-only.

## Core rule

The chrome stays still; the middle changes.

Moving between sections replaces **only the main pane**. The sidebar, bottom bar, and menus remain in place so the user never loses their bearings.

```
┌──────────┬───────────────────────────┐
│          │                           │
│ sidebar  │      main pane            │  ← only this swaps
│ (stays)  │  topic / view / archive   │
│          │                           │
├──────────┴───────────────────────────┤
│ bottom bar (stays)                   │
└──────────────────────────────────────┘
```

## Layout of files

A topic shows its files in a shape the user picks. **The shape decides which files are on screen** — there is no property on a file that makes it important.

A layout has a number of slots. Files fill them in order. Everything past the last slot is off screen.

| Layout | Slots | Shows |
|--------|-------|-------|
| Single | 1 | The first file |
| Split | 2 | The first two, side by side |
| Large left / Large right | 3 | A hero and two smaller |
| Row | all | Every file, in a row |
| Grid | all | Every file, wrapped |

So with five files: a grid shows all five, `Large left` shows three, and `Single` shows one. In every case the other files are **not on screen at all** — not collapsed, not below a divider. The only place they appear is the arrange overlay.

### Why prominence is not a flag

A file being "the important one" is a fact about the topic's arrangement, not about the file. Storing it twice — as a flag *and* as an order — means the two can disagree, and then the app has to pick a winner. So the topic stores `file_layout`, each file stores `order_index`, and everything else is derived by [`layout/topic_file_slots.dart`](layout/topic_file_slots.dart):

| Question | Answer |
|----------|--------|
| Which files are on screen? | `shownFiles(ordered, layoutId)` |
| Which are not? | `hiddenFiles(ordered, layoutId)` |
| What if the layout needs more files than exist? | `effectiveLayoutId` falls back for drawing and **leaves the stored layout alone**, so adding the files back restores it |
| What if the user never picked a layout? | Stored `auto`. 1 file → single, 2 files → split, 3+ → large left. Arrange writes a real id only when the pick is not that default |

### Rules that follow

- **A new file is added first**, so it is always on screen. Every layout has at least one slot, and a file you just created that you cannot see would be a bug you could not diagnose.
- **A hidden file is never lost.** Deleting and archiving are explicit actions with their own UI; being off screen is neither.
- **Choosing a smaller layout hides files, it does not reorder them.** Switching back shows the same files in the same places.
- **Phone shows every file of the topic**, one at a time, in order. There are no layouts on phone — a file hidden on desktop is still in the swipe row. Position (`n / total`) is only in the reorder sheet. The **screen structure is locked** — see [Phone screen structure](#phone-screen-structure).

| Concern | Files |
|---------|-------|
| The layouts themselves | [`layout/file_layouts.dart`](layout/file_layouts.dart) |
| Which files a layout reaches | [`layout/topic_file_slots.dart`](layout/topic_file_slots.dart) |
| Drawing them | [`layout/file_layout_board.dart`](layout/file_layout_board.dart) |
| Rearranging | [`arrange/`](arrange/) — desktop overlay; phone reorder sheet |

### Arranging

Arranging is a **mode**: the user opens it from the bottom bar (desktop) or the phone bottom tools, moves files, and commits. Nothing is written until Done, and Escape / Cancel leaves everything as it was.

**Desktop** overlay has three bands, walked with up/down:

| Band | What it holds | Actions |
|------|---------------|---------|
| Shown | The layout, previewed as the shared read-only file | Tap a file to make it first, right-click to take it off screen, left/right to cycle |
| Not on screen | The hidden files, in a strip | Tap to bring one back into the last slot |
| Layouts | The pickable shapes | Click or left/right; layouts needing more files than the topic has are disabled |

On commit it writes one `order_index` per file and one `file_layout` on the topic.

**Phone** has no layouts, so arrange is only the swipe row: a `ReorderableListView` of file names ([`arrange/phone_file_reorder_sheet.dart`](arrange/phone_file_reorder_sheet.dart)). Done calls `reorderTopicFiles` and does not change `file_layout`.

### Bring file (Home visit)

Home can **project** one or more files that still belong to other topics. ⌘K (or the phone Bring control) opens a searchable overlay: first word matches the topic, the rest the file name. Desktop rolls the matches sideways, each card showing the shared read-only file (not marker text); phone is a **bottom sheet of names** with each row wearing the topic colour ([`bring_file/phone_bring_file_sheet.dart`](bring_file/phone_bring_file_sheet.dart)). Choosing a file does not move it — `topic_id` stays put. Visits join Home’s order (newest first until rearranged). On desktop the layout’s slot count decides what is on screen; on phone every file in that order is in the swipe row. Arrange and cycle-files reorder the mixed list: visiting files keep their source `order_index`; the mixed order is stored locally. Each visiting pane is editable and wears its source topic’s colour. The file ⋯ menu has **Dismiss brought file**; that ends that visit only. Visits are stored locally until dismissed (including after restart).

### Phone screen structure

This layout is settled. Do not go back to a reserved well behind the tools, a topic-coloured middle, or pills that sit on a different colour from the file canvas.

```
┌─────────────────────────────┐
│ header (off-white)          │  Home and views: solid. Other topics:
│         ~~~~ ombre ~~~~     │  off-white at the top, light topic
├─────────────────────────────┤  wash only in the lower third.
│                             │
│  grey middle                │  Same colour under the file and the
│   ┌───────────────────┐     │  pills. File frame ends above the
│   │ framed file card  │     │  bubbles. Card shadow for depth;
│   │                   │     │  pills have no lift shadow.
│   └───────────────────┘     │
│   ( )  ( )  ( )  pills      │  One scrolling row, above the footer
├─────────────────────────────┤  — not overlapping it.
│ footer (off-white, thin)    │  Separate band. Home indicator
└─────────────────────────────┘  included.
```

Shell: [`shell/phone_app_shell.dart`](shell/phone_app_shell.dart). File roll: [`topic/phone_topic_view.dart`](topic/phone_topic_view.dart). Colours: [UI](../ui/AREA.md).

### The topic canvas composition

How a topic is laid out on screen, top to bottom — matching v1:

1. **Topic header** floats at the top ([`topic/topic_header.dart`](topic/topic_header.dart)): the topic name (and emoji when it is not the main topic), and the `+` that adds a file. It does not scroll away.
2. **Files begin immediately under the header**, top-aligned. The canvas reserves the header's height and the bottom bar's; the files never sit vertically centred in leftover space.
3. The add-file control lives **only** on the header — not also on the bottom bar — so there is one place to look.

### Who rebuilds

Listeners sit as low as they need to. The open document is not remounted because startup or the sidebar refreshed.

| Change | What rebuilds |
|--------|----------------|
| Language (theme / direction) | [`app.dart`](../../app.dart) rebuilds `MaterialApp` only |
| Sidebar, mode, canvas wash, bottom bar | Shell `ListenableBuilder` — chrome only. [`TopicView`](topic/topic_view.dart) is a **stable child**, not rebuilt by that listen |
| Open topic, file list / names / order, layout | `TopicView` listens itself |
| Document body or embeds (this device or another) | [`SuperDocumentEditor`](../files/editor/super_document_editor.dart) listens itself and applies into the open editor. If a key is down, the apply waits |

Do not wrap `MaterialApp` or the topic canvas in `Consumer<AppState>` / a shell listen that rebuilds the files on every notify.

## Sections

| Section | Entry | Main pane |
|---------|-------|-----------|
| Topic | Sidebar topic | [`topic/topic_view.dart`](topic/topic_view.dart) — files laid out |
| Task view | Sidebar view | [`../objects/views/task_view_pane.dart`](../objects/views/task_view_pane.dart) — grid of list frames |
| Objects map | Sidebar **Objects map** (below topics) | [`../objects/diagram/object_diagram_pane.dart`](../objects/diagram/object_diagram_pane.dart) — `interactive_graph_view` canvas; pan/zoom/drag always; double-click chip to open (several at once); × or Close all; Arrange by links (clears saved spots); hide unconnected unless configured; tag filter, color modes |
| Archive | Sidebar archive | [`archive/`](archive/) — paginated grid, search, read-only preview |

### Archive

Opening a topic under **Archive** replaces the main pane with [`archive/archive_topic_view.dart`](archive/archive_topic_view.dart) — desktop and phone use the same view. Phone hides the insert bar and uses the bottom bar’s trash for delete-mode. The page title is the topic headline (icon + name, same as the live topic) with `- Archive`. In the sidebar, archive type folders start closed.

| Piece | Does |
|-------|------|
| Search pill | Filters already-loaded cards immediately; after a short pause the server searches names and heading lines |
| Preview | Spotlight of the selected file: the shared read-only file ([`FilePreview`](../files/editor/file_preview.dart)) from `GET /files/:id/agent-text`. No `SuperDocumentEditor`, no marker text |
| Grid | Pages of 24 cards ([`archive_file_grid.dart`](archive/archive_file_grid.dart)), also topic-tinted; scroll near the bottom loads more |
| File ⋯ / right-click | Unarchive (file returns first in its topic) or delete |
| Bottom-bar trash | Delete mode: multi-select cards, then confirm a real cascade delete |

Archived files are not editable. The live topic canvas is unchanged.

### Task view page

Opening a view replaces the main pane with a **grid of file-like frames**. Each frame is one list (a section, or a topic when grouped that way). The page chrome is a small floating capsule above the bottom bar on desktop (same language as the bottom menus). On phone those same controls sit **in** the bottom bar, only while a view is open:

| Control | Does |
|---------|------|
| Toggle (swap) | Alternates sections ↔ topics (`layout_config.display_mode`) |
| Add section | Always visible; dormant in topics mode |
| Reorder | Mode: drag frames to reorder sections or topics |

Right-click a **section** frame to edit name, important flag, and section color. **Topic** frames wear the topic colour. Task behaviour inside a frame matches the in-file list: mark/unmark, Active/Done, and right-click **Reorder tasks** (glass chips; tap outside ends the mode).

Phone uses its own shell — see [Phone screen structure](#phone-screen-structure). The two rolls are independent. A pending AI review opens as a full-width dialog with Current / Suggested toggle ([`lookalike_review_dialog.dart`](../production_agent/lookalike_review_dialog.dart)); it is not dismissible until Finish or Discard.

Tapping outside the focused editor (canvas, empty padding — not another field) unfocuses it, hides the caret, and closes the keyboard, on phone and desktop ([`shell/dismiss_focus_on_outside_tap.dart`](shell/dismiss_focus_on_outside_tap.dart)). The **bottom menu** is excluded: insert and other bar tools must stay usable while typing. An open object is also excluded so a tap on its frame does not kill the field. On phone, the first pill is arrows plus enter/leave (Tab / Escape have no keys). Those arrows never mirror in Hebrew.

## What the sidebar allows

- Browse topics and open one in the main pane
- Open user-created task views
- Open the **Objects map** (info object graph) — listed after topics
- Reach the archive
- Create a topic, view, tag, or **topic type** from the centered sidebar **+** — a context-menu bubble lists the choices; each opens its own create dialog (tags are filtered on the objects map, not listed as a sidebar section). Creating a type does not open the type editor; a short hint points at Preferences.
- Topic types are user-defined. The sidebar has one section per type, plus Main (Home) and Others (untyped non-Home topics). Configure types from Preferences. Right-click a typed topic to make it that type's template.

The sidebar is navigation only. It never edits content.

## Menus exposed

| Menu | Where | Purpose |
|------|-------|---------|
| Topic / file context menu | Right-click in topic view, or the `⋯` on a file | Archive, delete — same bubble either way |
| Sidebar topic | Right-click a topic | Edit, duplicate, delete, **use as type template** — `AppContextMenu`, not a native popup |
| Text context menu | Right-click inside a document | Formatting, clipboard, **Connect info…** |
| Table cell menu | Right-click in a table cell | Add column, plus text actions |
| View section menu | Right-click a section frame on the view page | Edit name / flag / color |
| View task menu | Right-click a task in a view frame | Reorder tasks (same mode as in-file) |
| View chrome | Floating capsule on the view page | Sections/topics, add section, reorder frames |
| AI actions | Bottom bar | Pinned actions, the actions menu, and the agent prompt — see [production agent](../production_agent/AREA.md) |
| Automations | Bottom bar | Manage rules — see [automations](../automations/AREA.md) |
| Preferences | Bottom bar | App settings, shortcut bindings, topic types |

Context menus are built on [`widgets/app_context_menu.dart`](widgets/app_context_menu.dart) so they behave and look consistent.

## Shortcuts

Shortcuts are user-rebindable. [`shortcuts/`](shortcuts/) owns the catalog of available actions, the stored bindings, and the dispatcher that routes a keystroke to an action. **Every row in Preferences is wired.** Non-text shortcuts are taken at the hardware keyboard (so they work without a caret, and so the editor cannot swallow them). Text shortcuts still need a caret. A press fires once: the hardware intercept and the Flutter [Shortcuts] map both see the key, so the dispatcher ignores a second delivery until KeyUp (size up/down may repeat).

| File | Role |
|------|------|
| [`shortcuts/shortcut_catalog.dart`](shortcuts/shortcut_catalog.dart) | Every bindable action (this is the Preferences list) |
| [`shortcuts/shortcut_bindings_store.dart`](shortcuts/shortcut_bindings_store.dart) | User overrides, persisted |
| [`shortcuts/app_shortcuts.dart`](shortcuts/app_shortcuts.dart) | Hardware intercept + keystroke map for the whole catalog |
| [`shortcuts/shortcut_dispatcher.dart`](shortcuts/shortcut_dispatcher.dart) | Keystroke → action |
| [`shortcuts/main_file_cycle.dart`](shortcuts/main_file_cycle.dart) | Rotate every live file in the topic (not only the on-screen band) |

| Catalog | Does |
|---------|------|
| Go home | Opens Home |
| Bring file | Search overlay of files from other topics; choosing one **visits** it on Home in the layout (same document, still owned by its topic). Repeat to visit more. Arrange and cycle include those visits. |
| Arrange | File arrange overlay (topic page) |
| Cycle files | ⌘[ and ⌘] rotate **every live file in the topic** in a circle (not only the layout’s slots; not archived). Topic-level chrome — applies immediately, even with no caret. Do not wait for KeyUp / `runAfterKeystroke` |
| Add file / topic / view | The same dialogs as the chrome |
| Assign task view | Assign dialog when a task has the caret |
| Agent / slot keys | Agent prompt (⌘⇧1), or the saved action in that bar seat |
| Text (bold, italic, underline, cut/copy/paste, size) | Embed fields via `runBlockTextAction`; Super Editor via `DocumentEditorController.applyTextAction`. Super Editor still handles ⌘B / ⌘I / ⌘C / ⌘V / ⌘X itself when it has focus |
| Insert object | Active file via `DocumentEditorRegistry` |
| Layout toggle | View page: sections ↔ topics |
| Language | English ↔ Hebrew (⌘E; after the keystroke, so the editor is not remounted mid-KeyDown) |

**Insert object** (not “blocks”): catalog category `objects` inserts into the **active** file via `DocumentEditorRegistry` — info, task list, table, graph (chart table), image. After insert, the caret enters the new object (first inner field); images with no field keep the block caret. The bullet list stays on the insert bar only (document structure, not an object); a paragraph has no button anywhere — it is what typing already does.

Default keys match the English name’s letter (`D`etails, `T`ask, `T`able, `G`raph, `I`mage). When two objects share a letter, keep that letter and vary the modifiers (task = ⌘⇧T, table = ⌘⌥T). **Move object** is ⌘⌥M (⌘⇧M is layout toggle).

**AI keys belong to the seat, not the action.** ⌘⇧1 is the agent; ⌘⇧2…⌘⇧7 fire whatever saved action sits in bar slots 1–6, and do nothing while a seat is empty. Moving an action to another seat moves its key with it, so there is no shortcut to pick when creating one. Rebinding a seat works like any other action and now survives a restart — `ShortcutBindingsStore.restore()` runs during `AppState.initialize()`.

## Rules

- Section changes swap the main pane only. Never rebuild or hide the sidebar and bottom bar on desktop.
- On desktop, preferences and automations sit at the **start** of the bottom bar (left in English, right in Hebrew). Document insert tools and AI stay in the remaining center, on the same baseline — not above the bar.
- On phone, those same parts sit in **one** horizontally scrolling row of bubbles. Swiping that strip is independent of swiping between files. When the caret is on or in an object, the **first** pill is arrows (left, down, up, right) plus enter/leave (Tab / Escape have no keys). The pad is locked LTR: left stays left and right stays right in Hebrew — the icons only *draw* a physical direction and never mirror. Table cells still flip with the Hebrew UI (visual left is a higher column). Do not change the locked [phone screen structure](#phone-screen-structure). There is no drag-up sheet.
- Navigation never mutates content. Opening, browsing, and arranging are separate from editing.
- Every menu action is also reachable without the menu where it makes sense (shortcut or inline control).
- Overlay modes (arrange, bring file, previews) must be cancellable without saving.
- File previews on arrange, bring-file, archive, and the AI diff are the shared read-only file — never marker/editor text.
- Use `core/platform/app_form_factor.dart` to branch desktop vs phone; do not check screen width inline.
- Visual constants come from [UI](../ui/AREA.md) — this area decides *what appears*, not what it looks like.
- Which files are on screen is derived from the layout and the order. Never add a field to a file to answer it.
