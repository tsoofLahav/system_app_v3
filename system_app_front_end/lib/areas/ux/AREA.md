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

A topic shows its files in a layout the user controls. The **essence** file is the topic's main file and gets prominence; other files arrange around it.

| Concern | Files |
|---------|-------|
| Layout options | [`layout/file_layouts.dart`](layout/file_layouts.dart) |
| Rearranging files | [`arrange/`](arrange/) — draft state, keyboard handling, overlay |
| Reorder mechanics | [`widgets/pane_reorder_logic.dart`](widgets/pane_reorder_logic.dart) |

Arranging is a **mode**: the user enters it, drags or uses the keyboard to reposition, and commits. Nothing persists until commit.

## Sections

| Section | Entry | Main pane |
|---------|-------|-----------|
| Topic | Sidebar topic | [`topic/topic_view.dart`](topic/topic_view.dart) — files laid out |
| Task view | Sidebar view | [`../objects/views/task_view_pane.dart`](../objects/views/task_view_pane.dart) |
| Archive | Sidebar archive | [`archive/`](archive/) — archived topics and files, read-mostly |

Phone uses dedicated shells ([`shell/phone_app_shell.dart`](shell/phone_app_shell.dart), [`topic/phone_topic_view.dart`](topic/phone_topic_view.dart)) because the sidebar cannot stay visible.

## What the sidebar allows

- Browse topics and open one in the main pane
- Open user-created task views
- Reach the archive
- Create a topic

The sidebar is navigation only. It never edits content.

## Menus exposed

| Menu | Where | Purpose |
|------|-------|---------|
| Topic / file context menu | Right-click in topic view | Rename, move, archive, change layout |
| Text context menu | Right-click inside a document | Formatting, clipboard, emoji |
| Table cell menu | Right-click in a table cell | Add column, plus text actions |
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
| [`shortcuts/main_file_cycle.dart`](shortcuts/main_file_cycle.dart) | Cycle which file is focused |

## Rules

- Section changes swap the main pane only. Never rebuild or hide the sidebar and bottom bar on desktop.
- Navigation never mutates content. Opening, browsing, and arranging are separate from editing.
- Every menu action is also reachable without the menu where it makes sense (shortcut or inline control).
- Overlay modes (arrange, bring file, previews) must be cancellable without saving.
- Use `core/platform/app_form_factor.dart` to branch desktop vs phone; do not check screen width inline.
- Visual constants come from [UI](../ui/AREA.md) — this area decides *what appears*, not what it looks like.
