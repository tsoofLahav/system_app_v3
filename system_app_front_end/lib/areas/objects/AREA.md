# Area: Objects (frontend)

Backend twin: [`system_app_back_end/areas/objects/AREA.md`](../../../../system_app_back_end/areas/objects/AREA.md) — storage, cascades, links, views.

## What this area owns

An object is a **piece of information with special qualities** — trackable, toggleable, orderable, filterable, or linkable — not plain prose.

This area owns **data, services, and type logic**. How an object is *presented inside a file* (caret, mark, frames, Move Mode, right-click) lives in [files](../files/AREA.md) under `editor/embeds/`.

| Type | Special quality (this area) | In-file presentation (files) |
|------|-----------------------------|------------------------------|
| `task_list` | Tasks as rows; order; done/active; **views** | List-like embed ([`../files/editor/embeds/inline_task_list.dart`](../files/editor/embeds/inline_task_list.dart)) |
| `info` | Knowledge piece; **links / object graph**; optional `payload.look` | One-text embed; first line = title ([`../files/editor/embeds/object_embed_widgets.dart`](../files/editor/embeds/object_embed_widgets.dart)); chrome **Design…** |
| `image` | Asset + caption payload; `width` 0–1 of the pane; optional `payload.look`; optional `images[]` row | Image embed (same file); right-click size + **Design…** + **Merge with next** |
| `table` | Grid (`payload.rows`); optional **chart** quality; optional `payload.look` | [`../files/editor/embeds/table_embed.dart`](../files/editor/embeds/table_embed.dart) (`RichTableEditor` + chart chrome); chrome **Design…** |

Payload helpers: [`data/table_payload.dart`](data/table_payload.dart), [`data/image_payload.dart`](data/image_payload.dart). Insert “graph” creates a table with `chart.enabled`.

```
files (presentation) ──thin overlay──► objects (data + type logic)
         │                                    │
         │  calls services / shows            │  tasks.status (done/active)
         │  controls for object fields        │  tasks ↔ views
         │                                    │  info ↔ links
         └────────────────────────────────────┘
```

**Done/active is data, not chrome.** It lives on the task row (`tasks.status`). The [`TaskMark`](tasks/task_mark.dart) widget is only the control that toggles that field — used in the file embed and in views.

**Thin overlay:** file embeds may import `objects/data/*` and shared controls like `TaskMark` to read/write object fields. Objects must **not** own document-flow, menus, or embed chrome — and should avoid importing the file editor.

## Tasks and views

**Three task orders.** List order (`list_order_index`), view-by-section (`view_task_memberships.order_index`), and view-by-topic (`topic_order_index`) are independent — first in the list can be fifth in a section and third under a topic. Reorder in one mode must not rewrite the other. Each frame sorts by the active mode’s index; do not globally sort then split.

**Active / Done zones.** Both the in-file list and the view pane split into Active then Done ([`tasks/task_zones.dart`](tasks/task_zones.dart)). Status is canonical on the task row (`active` / `done`); never a per-view done flag. Checking done in a view updates the same row in the file, and vice versa.

**Shared task surface.** [`tasks/task_list_surface.dart`](tasks/task_list_surface.dart) owns the local-row model (controllers / focus / ids / done + optimistic order). Rows keep a stable widget key when a new task gets its id so Enter does not remount the field. Segments are `task:<id>`. It mutates UI **before** the API. File and view both read [`AppState.tasksById`](../../../core/app_state.dart) so a title, done flag, delete, or description link is the same task everywhere. Persistence goes through [`tasks/task_list_bridge.dart`](tasks/task_list_bridge.dart):

| Host | Bridge |
|------|--------|
| In-file embed | [`tasks/file_task_list_bridge.dart`](tasks/file_task_list_bridge.dart) → list order / move APIs |
| View frame | [`views/view_frame_task_list_bridge.dart`](views/view_frame_task_list_bridge.dart) → membership rewrite + `createTaskInView` |

**Drag + Reorder Mode.** Payload in [`tasks/task_drag_data.dart`](tasks/task_drag_data.dart). Glass chips, no handles. Same surface for files and view frames. Cross-frame drops in a view update membership section/topic then refresh. ⌘O: in-file list with caret → that list; else if a table cell (or table block) has the caret → that table’s row reorder (chart: columns); else if a view is open → that pane’s task reorder; else sidebar. While view task-reorder is on, drag a chip onto another frame (title, padding, or empty card) to move it — end of Active, or Done if the task is done. Dropping on a chip or gap in that frame still inserts at that slot.

**Empty titles.** Created with `title: ""` — the field stays blank, no placeholder. Enter on empty exits / unfocuses; Backspace on empty removes the row. Typing or pasting into a row that is still being created must not be replaced by that empty create payload: keep the local text if a save is pending or the refresh is empty, and flush the title once the id arrives. Pasting several lines (or `;`-separated items) into a task title creates one task per line — first line stays in the focused row, the rest are inserted after it. A mark that already spans several tasks still replaces those titles as one paste. In a file, the last empty task + empty title + Backspace deletes the whole task-list object (`onDeleteObject`); do not DELETE the task first — cascade on the object already removes it. Views show an unsaved empty seed in a new empty section so there is somewhere to type; **that placeholder is dropped as soon as a real task is moved or placed into the section**. A mark that covers a task **end to end** (including Shift+arrows across several tasks) deletes those tasks on Backspace/Delete/Cut, not just their titles. If every task is marked that way, one empty task stays — delete the object from chrome or empty Backspace on the last unit.

**Create in a view frame.** The new task gets only that frame’s placement (section / topic key). Uncategorized and No topic stay empty — do not inherit a sibling’s section, topic, or home list. `after_task_id` is insert order only.

**Section cadence.** Each named section is `routine` or `one_time` (`layout_config.sections[].cadence`, plus a stable `key`). Complimentary automation tasks may only sit in a **routine** section. Creating a section also creates an off **section window** automation (see automations `AREA.md`).

**Complimentary tasks.** Rows with `source_automation_id` + `complimentary_role` (`input` / `review`) are completed by the automation pipeline, not the checkbox. Press the title to open input or review. They recycle (unmark) at the next section-window start.

**Views.** A user-made list a task can appear in without being copied. **A task belongs to at most one view** — choosing a view replaces any previous one (`setTaskView`). Create from the sidebar **+**; rename via right-click → Edit on a view; delete via right-click → Delete (memberships go, tasks stay). Reorder views in sidebar reorder mode (⌘O, or Preferences). Assign from a task’s right-click **Choose view…** in a **file** (or ⌘J). On the **view page**, ⌘J opens **Place…** (view / section / topic / list) instead of that view-only menu. If several tasks in the **same list** are marked, the chosen placement applies to all of them. UI: [`views/assign_task_view_dialog.dart`](views/assign_task_view_dialog.dart), [`views/place_task_dialog.dart`](views/place_task_dialog.dart).

**View page.** [`views/task_view_pane.dart`](views/task_view_pane.dart) is placement chrome only: grid of section/topic frames ([`views/view_list_frame.dart`](views/view_list_frame.dart) → [`views/view_frame_task_list.dart`](views/view_frame_task_list.dart)). Each frame hosts `TaskListSurface`. Empty leftover buckets (Uncategorized / No topic) stay hidden until they have tasks; named empty sections the user created stay. Floating chrome toggles sections↔topics, adds sections, and starts frame reorder (exit by tapping empty canvas, not frames). Each display mode keeps its own order in `layout_config`: `section_order` / `topic_order`. Task right-click is text actions, **Reorder tasks**, Connect info, **Place…**, Delete. **Place…** ([`views/place_task_dialog.dart`](views/place_task_dialog.dart)) picks topic (searchable), that topic’s live task lists (`GET /topics/:id/task-lists`), view, and that view’s sections — applied view → section → topic → list, with the leave-home-list confirm when list or topic would drop a home list. Title right-click is edit/delete section only; deleting a section moves its tasks to Uncategorized. Delete warns only when the task has a home list.

**Task list header.** In-file lists show a title line (`task_lists.title`) via the surface when the file bridge enables it; view frames use the frame title instead.

```
task ──┬── shown inline in its file (home list)
       └── shown in at most one view
```

## Info and the object graph

An info object holds knowledge (`title`, `body`, …). In the file, title and body edit as **one text field** (first line → `title`, rest → `body`) with no placeholder explaining that; diagrams and the API still see separate fields. Graph edges are keyed by **`objects.id`**. Removing an info from a file (any path) must delete the object row — the map is every info in the workspace, so orphans stay visible until cascade-deleted (see backend objects `AREA.md` deletion).

| Kind | Meaning |
|------|---------|
| `related` | **info ↔ info** only (stored directed; UI treats undirected) |
| `description` | Marked text → an info (`anchor`: `{ segment_id, start, end }` on the **host**). **Task titles** store the link on the task (`source_type=task`, `anchor.segment_id` = `task:{id}`) so the underline stays on that task when rows are inserted above it. Other objects store it on the host object. |

Description and related stay separate. Text inside an info does **not** create a map edge (underline + bubble only). Chrome **Add connection…** is related. Deleting one kind does not delete the other.

Connect info on a task row works in the file **and** in a view (same `TaskListSurface`). The span is stored on that task id, not the list slot. List **title** Connect info still uses the host task-list object.

**Tags.** Freeform workspace tags (`tags.icon` + colour) assign to objects via `entity_type=object`. Topic types are not tags — leftover classification names (`project` / `process` / …) are excluded from the object-tag UI (map filter and assign-tag dialog).

**UI here:**
- Create tag via sidebar **+**; assign tags on info **chrome** (block caret / object menu)
- Info **field**: formatting + **Connect info…** / **Remove connection** (description). Info **chrome**: Add tag + **Add connection…** (related, infos only). ⌘L in an object field (info / task / table) opens Connect info (description only). Otherwise ⌘L inserts a list. Chrome **Add connection…** stays related-only.
- Description: right-click marked text / caret line in an object field → Connect info… (empty-title infos are hidden, including ones the graph used to label `Info`). Offers: names similar to the marked text, then infos in the same topic, then the rest. Searching by name drops the similar-text offers and lists the topic first, then everywhere else. Dark-teal glyphs + 1px underline, hover bubble (stays open while the pointer is on the connected text or the bubble, and the bubble scrolls), double-click / double-tap opens the target info in its file. Right-click a connected span for **Remove connection**. Typing before a connected span moves the underline with those glyphs (anchors remap and PATCH).
- **Objects map** ([`interactive_graph_view`](https://pub.dev/packages/interactive_graph_view)): info nodes + related edges; pan/zoom; drag to move — the same while cards are open. The package has no layout or persistence — we own `NodeWidget.position`. Coordinates live on the object (`diagram_x` / `diagram_y`); unsaved nodes get a connected layout (layers along links, then spring forces) so related objects sit near each other. **Arrange by links** (map chip, or Graph configuration) throws every saved spot away and writes that connected layout; a later drag is saved until Arrange is pressed again. The stored point is the **center of the circle that fits the card**. Double-click a chip opens a content-tight card on that same center (several may be open); every other closed node moves out along its ray by `R_open − R_closed`. The open card is a pane overlay that follows the chip — not a larger graph node. Close with × (that card) or **Close all**. Isolated objects stay off the map unless Graph configuration shows them. Tag filter above the bottom bar lists object tags only (not topic types); topic/tag color modes. Right-click a chip or open card: **Add connection…** (related, infos only) and **Go to source**. Linked spans on an open card: double-click / double-tap pans to the target chip at the current zoom, then opens it the same way as a chip double-click. Cards stay editable.

In-file editing of the unified info text is presentation (files).

## Image and table (data)

| Type | Data |
|------|------|
| `image` | Payload: url/path/caption; `width` is 0–1 of the file pane; optional `look` (`card` / `glass` / `outline` / `fill` / `plain`); optional `greyscale`; optional `images[]` when several pictures share one object (first pane is also on `url` / `caption`) |
| `table` | Payload: `rows` + optional `chart` (`enabled`, `chartType`, `colors[]`) + optional `look` (`grid` / `glass` / `outline` / `fill` / `lined` / `plain`) — see [`data/table_payload.dart`](data/table_payload.dart) |
| `info` | Title/body on `information_pieces`; optional `objects.payload.look` (`card` / `glass` / `outline` / `fill` / `ruled` / `plain`) so the card chrome can persist |

Each object remembers its own look (chrome right-click **Design…**). Omitted `look` is today’s default. Task lists have no look picker. Table normalize must keep `look`. Legacy ids (`none` / `frame` / `greyscale` / `open`) still load.

Graph/table cells and info title/body live on the object row, not in marker text. Concurrent user + agent edits are resolved in files ([`../files/editor/edit_conflict.dart`](../files/editor/edit_conflict.dart)): inbound wins unless that embed is dirty **and** inbound changed it, then the user chooses. A dirty object does not block inbound for a different object in the same file.

Agent text and API shapes: backend objects `AREA.md` + production agent prompt. “Object graph” (links map) is separate from chart tables.

## Structure

| Folder | Role |
|--------|------|
| [`data/`](data/) | Models and API services (objects, tasks, views, …) |
| [`tasks/`](tasks/) | Shared task UI: row, mark, drag payload, Active/Done zone helper |
| [`views/`](views/) | Task view pane and display config |
| [`tags/`](tags/) | Create / assign object tags |
| [`links/`](links/) | Connection picker + description hover bubble |
| [`diagram/`](diagram/) | Objects map pane (`interactive_graph_view`) |

In-file embed widgets: [`../files/editor/embeds/`](../files/editor/embeds/).

## Rules

- A task exists once. Views reference it — never copy task state into a view.
- Toggling done anywhere updates the one canonical row everywhere.
- Ordering is explicit and persisted.
- Creating an object must also place its embed block (API), or it is invisible in the file.
- Deleting an embed goes through the object service so the backing row is cleaned up.
- Related links are info ↔ info only. Description links are host object → info, or **task → info** for a title span. Creating a description never writes related.
- Do not put document caret/mark/menu rules here — that is files.
- Topic types are not tags. Object-tag UI excludes type names and leftover classification tags.

## Shipped vs next

**Shipped (data):** task CRUD/status/order; view membership pane; empty titles; object create/delete with embed insert.

**Shipped (behaviour):** Active/Done zones; optimistic drag reorder in list embed and view pane; independent list vs section vs topic order; view grid (sections/topics), Place… dialog, hide empty Uncategorized/No topic, section edit, frame reorder, ⌘O and drag-onto-frame task reorder on the view page; object tags; related info↔info links; objects map (`interactive_graph_view`: persisted positions, connected-first layout, Arrange by links to forget saved spots, hide unconnected by default, several open cards with ΔR ray push, pan/zoom/drag while open, close with × or Close all, object-tag filter, color modes). Map right-click: Add connection / Go to source. Open-card description spans pan to the target chip at the current zoom, then open it.

**Shipped (presentation, in files):** list-like task embed; info title/body + tag chips (field: Connect info; chrome: add tag / related connection); table embed (+ chart quality); Move Mode; description underlines + hover bubble (stays open on the bubble so it can scroll) + double-click / double-tap to open the info in its file. Task-title description links also show in views. Typing before a connected span keeps the underline on those glyphs.

**Next (this area):** non-info map nodes; convert-selection → create Info.
