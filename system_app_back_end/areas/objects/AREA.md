# Area: Objects (backend)

Frontend counterpart: [`system_app_front_end/lib/areas/objects/AREA.md`](../../../system_app_front_end/lib/areas/objects/AREA.md).

## What an object is

An object is a **piece of information with special qualities** — something that behaves differently from plain text because it can be tracked, toggled, ordered, filtered, or linked.

Plain sentences live in the document body. Anything the system needs to *reason about* becomes an object.

Objects live in the `objects` table and appear inside a file through an `embed` block that points at `objects.id`. The [files area](../files/AREA.md) owns **placement**; this area owns **content and behavior**.

| Type | Backing storage | Special quality |
|------|-----------------|-----------------|
| `task_list` | `task_lists` + `tasks` | Ordering, done/active, views |
| `info` | `information_pieces` | Linkable into a graph |
| `image` | `objects.payload` | Uploaded asset reference |
| `graph` | `objects.payload` | Rendered data series |

## Tasks

Tasks are the richest object type — a sub-part of this area, not a separate one.

**Order.** Every task carries `list_order_index` within its `task_list`. Users reorder freely; order is explicit, not derived from creation time. Reordering rewrites indices for the whole list so they stay dense.

**Done / active toggle.** `tasks.status` is `active` or `done`. A task exists **once**. Marking it done anywhere updates the single row and is reflected everywhere it appears.

**Views.** A view is a user-made list that a task can appear in without being copied. Membership lives in `view_task_memberships`, with its own ordering per view.

```
tasks ──< view_task_memberships >── views
```

Views are membership and filtering only. **Never add per-view status columns** — that would duplicate task state.

## Information and the object graph

An `info` object holds a piece of knowledge (`title`, `body`, `metadata`).

Info objects can be **linked** — and links are not restricted to info. The `links` table connects any entity to any other:

| Column | Meaning |
|--------|---------|
| `source_type`, `source_id` | One endpoint |
| `target_type`, `target_id` | The other endpoint |

So an info piece can link to a task, a task to another task, an info to several infos. Together these edges form a **graph of objects** across the whole workspace, independent of which file each object sits in.

## Deletion

Deleting anything that contains objects must cascade, or the database keeps orphans that still appear in agent text.

`services/delete_cascade.py` owns cascades for task, object embed, file, topic, view, tag, workspace, and automation. Route handlers must call it rather than deleting rows directly.

## Modules

| Module | Role |
|--------|------|
| [`routes/objects.py`](routes/objects.py) | Create/update/delete embeds; insert the embed block into the file |
| [`routes/tasks.py`](routes/tasks.py) | Task CRUD, status, due date |
| [`routes/task_lists.py`](routes/task_lists.py) | Task list contents and reorder |
| [`routes/information.py`](routes/information.py) | Info pieces |
| [`routes/views.py`](routes/views.py) | Views and memberships |
| [`services/task_list_order.py`](services/task_list_order.py) | Canonical ordering within a list |
| [`services/delete_cascade.py`](services/delete_cascade.py) | Cascade rules for every container |

## Rules

- A task exists once. Views reference it; they never copy it.
- Ordering is explicit (`list_order_index`), never implied by id.
- Creating an object via `POST /files/:id/objects` must also insert its embed block — an object with no block is invisible.
- Never delete a container without its cascade.
- Any object may link to any object; do not hardcode allowed link pairs.
