# Area: Objects (frontend)

Backend twin: [`system_app_back_end/areas/objects/AREA.md`](../../../../system_app_back_end/areas/objects/AREA.md) — read it for storage, cascades, and the link graph.

## What an object is

A **piece of information with special qualities** — something the app can track, toggle, order, filter, or link, rather than plain prose.

Objects appear inside a document through an embed block. The [files area](../files/AREA.md) decides **where** the object sits in the text; this area renders and edits **what it contains**.

| Type | Widget | Special quality |
|------|--------|-----------------|
| `task_list` | [`embeds/inline_task_list.dart`](embeds/inline_task_list.dart) | Order, done/active, views |
| `info` | [`embeds/object_embed_widgets.dart`](embeds/object_embed_widgets.dart) | Linkable into a graph |
| `image` | same | Uploaded asset |
| `graph` | same | Rendered series |

## Tasks

**Order.** Tasks carry an explicit index inside their list. The user reorders by dragging ([`tasks/task_drag_data.dart`](tasks/task_drag_data.dart)); order is never inferred from creation time.

**Done / active.** A single toggle on the task row ([`tasks/task_mark.dart`](tasks/task_mark.dart)). The task exists once — checking it off in a view updates the same row shown inside the file, and vice versa. Never keep a local per-view "done" flag.

**Views.** A view is a user-made list a task can appear in without being copied. [`views/task_view_pane.dart`](views/task_view_pane.dart) renders one view as the main pane; [`views/task_view_display.dart`](views/task_view_display.dart) holds display config. A task can sit in several views at once, each with its own ordering.

```
task ──┬── shown inline in its file
       ├── shown in view "This week"
       └── shown in view "Errands"
        (one row, three places)
```

## Info and the object graph

An info object holds a piece of knowledge. Info objects can link to tasks, to other info, and in principle to any object — those edges form a graph across the workspace, independent of which file each object lives in.

Rendering the graph is not built yet; the links exist on the backend.

## Structure

| Folder | Role |
|--------|------|
| [`embeds/`](embeds/) | Widgets that render objects inside a document |
| [`tasks/`](tasks/) | Task row, done mark, drag payload |
| [`views/`](views/) | Task view pane and display config |
| [`data/`](data/) | Models and API services for objects, tasks, and views |

## Rules

- A task exists once. Views reference it — never copy task state into a view.
- Toggling done anywhere must update the one canonical row and reflect everywhere.
- Ordering is explicit and persisted; never rely on list position alone.
- Creating an object must also place its embed block, or it will be invisible in the file.
- Deleting an embed goes through the object service so the backing row is cleaned up.
- Object widgets keep the document's text rhythm — they sit in the flow, not in boxed-off panels.
