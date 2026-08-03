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

### Rules that follow

- **A new file is added first**, so it is always on screen. Every layout has at least one slot, and a file you just created that you cannot see would be a bug you could not diagnose.
- **A hidden file is never lost.** Deleting and archiving are explicit actions with their own UI; being off screen is neither.
- **Choosing a smaller layout hides files, it does not reorder them.** Switching back shows the same files in the same places.
- **Phone shows the same files**, stacked one per row, because two panes cannot sit side by side. A file hidden on desktop stays hidden on the phone.

| Concern | Files |
|---------|-------|
| The layouts themselves | [`layout/file_layouts.dart`](layout/file_layouts.dart) |
| Which files a layout reaches | [`layout/topic_file_slots.dart`](layout/topic_file_slots.dart) |
| Drawing them | [`layout/file_layout_board.dart`](layout/file_layout_board.dart) |
| Rearranging | [`arrange/`](arrange/) — draft state, keyboard handling, overlay |

### Arranging

Arranging is a **mode**: the user opens it from the bottom bar, moves files, and commits. Nothing is written until Done, and Escape leaves everything as it was.

The overlay has three bands, walked with up/down:

| Band | What it holds | Actions |
|------|---------------|---------|
| Shown | The layout, previewed | Tap a file to make it first, right-click to take it off screen, left/right to cycle |
| Not on screen | The hidden files, in a strip | Tap to bring one back into the last slot |
| Layouts | The pickable shapes | Click or left/right; layouts needing more files than the topic has are disabled |

On commit it writes one `order_index` per file and one `file_layout` on the topic.

### The topic canvas composition

How a topic is laid out on screen, top to bottom — matching v1:

1. **Topic header** floats at the top ([`topic/topic_header.dart`](topic/topic_header.dart)): the topic name (and emoji when it is not the main topic), and the `+` that adds a file. It does not scroll away.
2. **Files begin immediately under the header**, top-aligned. The canvas reserves the header's height and the bottom bar's; the files never sit vertically centred in leftover space.
3. The add-file control lives **only** on the header — not also on the bottom bar — so there is one place to look.

## Sections

| Section | Entry | Main pane |
|---------|-------|-----------|
| Topic | Sidebar topic | [`topic/topic_view.dart`](topic/topic_view.dart) — files laid out |
| Task view | Sidebar view | [`../objects/views/task_view_pane.dart`](../objects/views/task_view_pane.dart) — grid of list frames |
| Archive | Sidebar archive | [`archive/`](archive/) — archived topics and files, read-mostly |

### Task view page

Opening a view replaces the main pane with a **grid of file-like frames**. Each frame is one list (a section, or a topic when grouped that way). The page chrome is a small floating capsule above the bottom bar (same language as the bottom menus):

| Control | Does |
|---------|------|
| Sections / Topics | Switches how frames are grouped (`layout_config.display_mode`) |
| Add section | Creates a section (sections mode only) |
| Reorder | Mode: drag frames to reorder sections or topics |

Right-click a **section** frame to edit name, important flag, and section color. **Topic** frames wear the topic colour. Task behaviour inside a frame matches the in-file list: mark/unmark, Active/Done, and right-click **Reorder tasks** (glass chips; tap outside ends the mode).

Phone uses its own shell ([`shell/phone_app_shell.dart`](shell/phone_app_shell.dart)) because the sidebar cannot stay visible, but the same [`topic/topic_view.dart`](topic/topic_view.dart) draws the files — it collapses the layout to one pane per row rather than being a separate screen.

## What the sidebar allows

- Browse topics and open one in the main pane
- Open user-created task views
- Reach the archive
- Create a topic
- Create a view

The sidebar is navigation only. It never edits content.

## Menus exposed

| Menu | Where | Purpose |
|------|-------|---------|
| Topic / file context menu | Right-click in topic view, or the `⋯` on a file | Archive, delete — same bubble either way |
| Text context menu | Right-click inside a document | Formatting, clipboard, emoji |
| Table cell menu | Right-click in a table cell | Add column, plus text actions |
| View section menu | Right-click a section frame on the view page | Edit name / flag / color |
| View task menu | Right-click a task in a view frame | Reorder tasks (same mode as in-file) |
| View chrome | Floating capsule on the view page | Sections/topics, add section, reorder frames |
| AI actions | Bottom bar | Run a prompt or a saved automation — see [production agent](../production_agent/AREA.md) |
| Automations | Bottom bar | Manage rules — see [automations](../automations/AREA.md) |
| Preferences | Bottom bar | App settings, shortcut bindings |

Context menus are built on [`widgets/app_context_menu.dart`](widgets/app_context_menu.dart) so they behave and look consistent.

## Shortcuts

Shortcuts are user-rebindable. [`shortcuts/`](shortcuts/) owns the catalog of available actions, the stored bindings, and the dispatcher that routes a keystroke to an action.

| File | Role |
|------|------|
| [`shortcuts/shortcut_catalog.dart`](shortcuts/shortcut_catalog.dart) | Every bindable action |
| [`shortcuts/shortcut_bindings_store.dart`](shortcuts/shortcut_bindings_store.dart) | User overrides, persisted |
| [`shortcuts/shortcut_dispatcher.dart`](shortcuts/shortcut_dispatcher.dart) | Keystroke → action |
| [`shortcuts/main_file_cycle.dart`](shortcuts/main_file_cycle.dart) | Rotate which of the shown files leads |

## Rules

- Section changes swap the main pane only. Never rebuild or hide the sidebar and bottom bar on desktop.
- On desktop, document insert tools join the centered bottom-bar group beside preferences / automations / AI — same baseline, not above the bar and not pinned to a screen edge.
- Navigation never mutates content. Opening, browsing, and arranging are separate from editing.
- Every menu action is also reachable without the menu where it makes sense (shortcut or inline control).
- Overlay modes (arrange, bring file, previews) must be cancellable without saving.
- Use `core/platform/app_form_factor.dart` to branch desktop vs phone; do not check screen width inline.
- Visual constants come from [UI](../ui/AREA.md) — this area decides *what appears*, not what it looks like.
- Which files are on screen is derived from the layout and the order. Never add a field to a file to answer it.
