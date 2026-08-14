# Area: Objects (frontend)

Backend twin: [`system_app_back_end/areas/objects/AREA.md`](../../../../system_app_back_end/areas/objects/AREA.md) — storage, cascades, links, views.

## What this area owns

An object is a **piece of information with special qualities** — trackable, toggleable, orderable, filterable, or linkable — not plain prose.

This area owns **data, services, and type logic**. How an object is *presented inside a file* (caret, mark, frames, Move Mode, right-click) lives in [files](../files/AREA.md) under `editor/embeds/`.

| Type | Special quality (this area) | In-file presentation (files) |
|------|-----------------------------|------------------------------|
| `task_list` | Tasks as rows; order; done/active; **views** | List-like embed ([`../files/editor/embeds/inline_task_list.dart`](../files/editor/embeds/inline_task_list.dart)) |
| `info` | Knowledge piece; **links / object graph** | One-text embed; first line = title ([`../files/editor/embeds/object_embed_widgets.dart`](../files/editor/embeds/object_embed_widgets.dart)) |
| `image` | Asset + caption payload | Image embed (same file) |
| `table` | Grid (`payload.rows`); optional **chart** quality | [`../files/editor/embeds/table_embed.dart`](../files/editor/embeds/table_embed.dart) (`RichTableEditor` + chart chrome) |

Payload helpers: [`data/table_payload.dart`](data/table_payload.dart). Insert “graph” creates a table with `chart.enabled`.

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

**Two orders.** A task has `list_order_index` in its home list and a separate `order_index` per view membership — first in the list can be fifth in a view.

**Active / Done zones.** Both the in-file list and the view pane split into Active then Done ([`tasks/task_zones.dart`](tasks/task_zones.dart)). Status is canonical on the task row (`active` / `done`); never a per-view done flag. Checking done in a view updates the same row in the file, and vice versa.

**Shared task surface.** [`tasks/task_list_surface.dart`](tasks/task_list_surface.dart) owns the local-row model (controllers / focus / ids / done + optimistic order). It mutates UI **before** the API. Persistence goes through [`tasks/task_list_bridge.dart`](tasks/task_list_bridge.dart):

| Host | Bridge |
|------|--------|
| In-file embed | [`tasks/file_task_list_bridge.dart`](tasks/file_task_list_bridge.dart) → list order / move APIs |
| View frame | [`views/view_frame_task_list_bridge.dart`](views/view_frame_task_list_bridge.dart) → membership rewrite + `createTaskInView` |

**Drag + Reorder Mode.** Payload in [`tasks/task_drag_data.dart`](tasks/task_drag_data.dart). Glass chips, no handles. Same surface for files and view frames. Cross-frame drops in a view update membership section/topic then refresh.

**Empty titles.** Created with `title: ""` and hint (`newTaskHint`) — never the literal “New task”. Enter on empty exits / unfocuses; Backspace on empty removes the row. In a file, the last empty task + empty title + Backspace deletes the whole task-list object (`onDeleteObject`); views keep a seed row.

**Views.** A user-made list a task can appear in without being copied. **A task belongs to at most one view** — choosing a view replaces any previous one (`setTaskView`). Create from the sidebar **+**; rename via right-click → Edit on a view. Assign from a task’s right-click **Choose view…** (files and views) or the shortcut. UI: [`views/assign_task_view_dialog.dart`](views/assign_task_view_dialog.dart).

**View page.** [`views/task_view_pane.dart`](views/task_view_pane.dart) is placement chrome only: grid of section/topic frames ([`views/view_list_frame.dart`](views/view_list_frame.dart) → [`views/view_frame_task_list.dart`](views/view_frame_task_list.dart)). Each frame hosts `TaskListSurface`. Floating chrome toggles sections↔topics, adds sections, and starts frame reorder (exit by tapping empty canvas, not frames). Each display mode keeps its own order in `layout_config`: `section_order` / `topic_order`. Right-click menu groups **list + topic** (leave the origin list — confirm when the task has a home list) separately from **section + view** (view-only placement; view choice replaces). Title right-click is edit/delete section only; deleting a section moves its tasks to Uncategorized. Delete warns only when the task has a home list.

**Task list header.** In-file lists show a title line (`task_lists.title`) via the surface when the file bridge enables it; view frames use the frame title instead.

```
task ──┬── shown inline in its file (home list)
       └── shown in at most one view
```

## Info and the object graph

An info object holds knowledge (`title`, `body`, …). In the file, title and body edit as **one text field** (first line → `title`, rest → `body`); diagrams and the API still see separate fields. Graph edges are keyed by **`objects.id`**. Removing an info from a file (any path) must delete the object row — the map is every info in the workspace, so orphans stay visible until cascade-deleted (see backend objects `AREA.md` deletion).

| Kind | Meaning |
|------|---------|
| `related` | Object ↔ object (stored directed; UI treats undirected) |
| `description` | Info → marked span in a file (`anchor`: file/block/segment + offsets) |

**Tags.** Freeform workspace tags (`tags.icon` + colour) assign to objects via `entity_type=object`. Topic type tags (`project` / `process` / …) stay for topic classification and are excluded from the object-tag UI.

**UI here:**
- Create tag via sidebar **+**; assign tags on info embeds (context menu)
- Info frame shows tag chips only; Add connection via context menu (no links list)
- Description: document **Connect info…**, hover bubble, double-tap opens the info
- **Objects map** ([`interactive_graph_view`](https://pub.dev/packages/interactive_graph_view)): info nodes + related edges; pan/zoom; drag to move (session-only layout); double-click expands editable card with ×; tag filter above bottom bar; topic/tag color modes

In-file editing of the unified info text is presentation (files).

## Image and table (data)

| Type | Data |
|------|------|
| `image` | Payload: url/path/width/caption |
| `table` | Payload: `rows` + optional `chart` (`enabled`, `chartType`, `colors[]`) — see [`data/table_payload.dart`](data/table_payload.dart) |

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
- Any object may link to any object; do not hardcode allowed link pairs.
- Do not put document caret/mark/menu rules here — that is files.

## Shipped vs next

**Shipped (data):** task CRUD/status/order; view membership pane; empty titles; object create/delete with embed insert.

**Shipped (behaviour):** Active/Done zones; optimistic drag reorder in list embed and view pane; independent list vs view order; view grid (sections/topics), section edit, frame reorder; object tags; related + description links; objects map (`interactive_graph_view`: drag move, double-click expand, session layout, tag filter, color modes).

**Shipped (presentation, in files):** list-like task embed; info title/body + tag chips (add tag/link via context menu); table embed (+ chart quality); Move Mode; right-click text menu including Connect info; description underlines + hover/double-tap.

**Next (this area):** non-info map nodes; persisted map layout; convert-selection → create Info.
