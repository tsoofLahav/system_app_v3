# Area: Objects (frontend)

Backend twin: [`system_app_back_end/areas/objects/AREA.md`](../../../../system_app_back_end/areas/objects/AREA.md) — storage, cascades, links, views.

## What this area owns

An object is a **piece of information with special qualities** — trackable, toggleable, orderable, filterable, or linkable — not plain prose.

This area owns **data, services, and type logic**. How an object is *presented inside a file* (caret, mark, frames, Move Mode, right-click) lives in [files](../files/AREA.md) under `editor/embeds/`.

| Type | Special quality (this area) | In-file presentation (files) |
|------|-----------------------------|------------------------------|
| `task_list` | Tasks as rows; order; done/active; **views** | List-like embed ([`../files/editor/embeds/inline_task_list.dart`](../files/editor/embeds/inline_task_list.dart)) |
| `info` | Knowledge piece; **links / object graph** | Title + body embed ([`../files/editor/embeds/object_embed_widgets.dart`](../files/editor/embeds/object_embed_widgets.dart)) |
| `image` | Asset + caption payload | Image embed (same file) |
| `graph` | Chart data (labels/values) | Table-like embed ([`../files/editor/embeds/graph_embed.dart`](../files/editor/embeds/graph_embed.dart)) |

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

**Drag + optimistic UI.** Payload in [`tasks/task_drag_data.dart`](tasks/task_drag_data.dart). In-file reorder is a **Reorder Mode** owned by files (glass frames, no handles). Local order updates immediately; list persist uses `PUT …/tasks/order` or `POST …/move` (cross-zone); view persist rewrites memberships (+ toggle when the zone changes). On failure, revert and show `reorderFailed`.

**Empty titles.** New tasks are created with `title: ""` and a hint (`newTaskHint`) — never the literal “New task”. Enter on an empty row exits the list (same as document lists).

**Views.** A user-made list a task can appear in without being copied. Create from the sidebar (**New view**); rename via right-click → Edit on a view. Assign from a task’s right-click menu or the **Add task to view** shortcut (caret must be on a task). Assign UI in [`views/assign_task_view_dialog.dart`](views/assign_task_view_dialog.dart).

**View page.** [`views/task_view_pane.dart`](views/task_view_pane.dart) is a **grid of fixed-width file-like frames** ([`views/view_list_frame.dart`](views/view_list_frame.dart)), each holding one list (section or topic). Floating chrome ([`views/view_chrome_menu.dart`](views/view_chrome_menu.dart)) has one **toggle** for sections↔topics, add-section (dormant in topics mode), and frame-reorder. Section defs live in `views.layout_config` ([`data/view_layout.dart`](data/view_layout.dart)). Inside a frame: Enter/Backspace add & delete (delete warns it removes the task from its home list too), mark/unmark, and **Reorder tasks** ([`views/view_task_list.dart`](views/view_task_list.dart)).

```
task ──┬── shown inline in its file (files embed)
       ├── shown in view "This week"
       └── shown in view "Errands"
        (one row, three places)
```

## Info and the object graph

An info object holds knowledge (`title`, `body`, …). Links connect **any** object to any other (info↔task, info↔info, …) via the backend `links` table — a workspace-wide graph, independent of which file each object lives in.

In-file editing of title/body is presentation (files). **Link create/navigate/query UI and rules belong here** as they grow — not inside the embed widget beyond a small entry point.

## Image and graph (data)

| Type | Data |
|------|------|
| `image` | Payload: url/path/width/caption |
| `graph` | Payload: `labels`, `values`, `chartType`, **`colors[]`** (one hex per variable; legacy `color` = first) |

Agent text and API shapes: backend objects `AREA.md` + production agent prompt.

## Structure

| Folder | Role |
|--------|------|
| [`data/`](data/) | Models and API services (objects, tasks, views, …) |
| [`tasks/`](tasks/) | Shared task UI: row, mark, drag payload, Active/Done zone helper |
| [`views/`](views/) | Task view pane and display config |

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

**Shipped (behaviour):** Active/Done zones; optimistic drag reorder in list embed and view pane; independent list vs view order; view grid (sections/topics), section edit, frame reorder.

**Shipped (presentation, in files):** list-like task embed; info title/body flow; graph table-like embed; Move Mode; right-click text menu on task/info fields.

**Next (this area):** **info links** UI and navigation on the object graph; convert-selection → Info as a product flow using object APIs.
