# Area: Objects (backend)

Frontend counterpart: [`system_app_front_end/lib/areas/objects/AREA.md`](../../../system_app_front_end/lib/areas/objects/AREA.md).

## What an object is

An object is a **piece of information with special qualities** — something that behaves differently from plain text because it can be tracked, toggled, ordered, filtered, or linked.

Plain sentences live in the document body. Anything the system needs to *reason about* becomes an object.

Objects live in the `objects` table and appear inside a file through an `embed` block that points at `objects.id`. The [files area](../files/AREA.md) owns **placement and in-file presentation**; this area owns **content, type logic** (tasks/views, info links), and cascades.

| Type | Backing storage | Special quality |
|------|-----------------|-----------------|
| `task_list` | `task_lists` + `tasks` | Ordering, done/active, views |
| `info` | `information_pieces` | Linkable into the object graph (links map) |
| `image` | `objects.payload` | Uploaded asset reference + caption. Agent `create_object` generates the picture and stores `/images/…`; the insert bar still creates an empty slot for the user to pick a file |
| `table` | `objects.payload` | Grid (`payload.rows`); optional **chart** quality (`payload.chart`) — pointer `[TABLE id]` or `[GRAPH id]` when chart is on |

Migration `007_table_object.sql` moves legacy `type=graph` rows into `table` + `chart`.

Every object has a stable id, file id, type, optional typed FKs / payload, and timestamps. The document owns position; the object owns data.

## Shared rules with the file

| Rule | Meaning |
|------|---------|
| Embed is a pointer | Marker line e.g. `[INFO id="N"]` / `[TASK_LIST id="N"]` / `[TABLE id="N"]` — no payload in the file |
| Top-level only | Never nested inside list or table fences in editor text |
| Create inserts the block | `POST /files/:id/objects` (and agent `create_object`) create the row **and** insert the embed at `block_index` via [`services/create_embed.py`](services/create_embed.py) |
| Delete cascades | `delete_object_embed_cascade` removes the object and strips the embed from `document_json` |

## Tasks

Tasks are the richest object type — a sub-part of this area, not a separate one.

**Order.** Every task carries `list_order_index` within its `task_list`. Users reorder freely; order is explicit, not derived from creation time. Reordering rewrites indices for the whole list so they stay dense (`active` ids then `done` ids). Views keep a separate `order_index` on `view_task_memberships`.

**Done / active toggle.** `tasks.status` is `active` or `done`. A task exists **once**. Marking it done anywhere updates the single row and is reflected everywhere it appears. List queries and the UI show Active then Done zones; `POST /tasks/:id/move` can place a task into a zone (including the same list).

**Empty titles.** `POST /task-lists/:id/tasks` accepts `title: ""` (blank row). Only a missing title key may default; never coerce empty string to `"New task"`.

**Views.** A view is a user-made list that a task can appear in without being copied. Membership lives in `view_task_memberships`, with its own ordering per view. **Product rule: a task belongs to at most one view at a time** (the client replaces memberships rather than stacking them). Section definitions, display mode (`by_section` / `by_topic`), and topic-frame order live in `views.layout_config` (JSON) — not separate tables. Memberships still carry `section_name` / `section_flag` for which section a task sits in.

```
tasks ──< view_task_memberships >── views
                              layout_config: sections, display_mode, topic_order
```

Views are membership and filtering only. **Never add per-view status columns** — that would duplicate task state.

**Membership GET enrichment.** Listing memberships includes the nested task plus home-topic fields (`topic_id`, `topic_name`, `topic_key`, `topic_color`) so the frontend can colour topic frames without extra round-trips.

**Create task in a view.** `POST /views/:id/tasks` creates a real `tasks` row with **`task_list_id` null by default** (orphan — no home list). Optional `task_list_id` places it into an existing list. `tasks.task_list_id` is already nullable. Deleting a task with a home list should warn; orphans need no “original list” warning.

**Task list header.** `task_lists.title` (migration `005`) is the list’s header — same role as info title. `PATCH /task-lists/:id` updates it. Membership/task payloads include `task_list_title` when the task has a home list.

## Information and the object graph

An `info` object holds a piece of knowledge (`title`, `body`, `metadata`). The file UI edits them as one text field (first line → `title`); storage and agent text stay title + body.

The `links` table is the workspace **object graph**, keyed by **`objects.id`** for object endpoints (migration `006` also adds `links.kind`, `links.anchor`, `tags.icon`).

| Column | Meaning |
|--------|---------|
| `source_type`, `source_id` | Host object (`info` / `task_list` / `table` / …). Related: one info. |
| `target_type`, `target_id` | Related: the other info. Description: the connected info. |
| `kind` | `related` (default) or `description` |
| `anchor` | Description span on the **host**: `{ segment_id, start, end }` (`file_id` optional) |

| Kind | Shape | How it is created |
|------|-------|-------------------|
| **Related** | **info ↔ info** only | Object chrome or map node → Add connection |
| **Description** | **Any object’s marked text → an info** | Field menu → Connect info… Stored on the host. Many spans per host are allowed. Self-links are rejected. |

If the marked text lives **inside an info**, creating the description **also upserts related** between those two infos so the objects map gets an edge. Text inside a task or table does not draw a map edge. Deleting one kind does **not** delete the other.

| Endpoint | Role |
|----------|------|
| `GET /objects/graph?workspace_id=` | Info nodes (title, body, topic_id/color, tag_ids, `diagram_x`/`diagram_y`) + related info↔info edges for the objects map (description edges skipped) |
| `PUT /objects/graph/positions` | Batch-write map coordinates `{ workspace_id, positions: [{ object_id, x, y }] }` |
| `GET/POST /objects/:id/links` | List / create connections. Related: `target_object_id` (info). Description: `target_object_id` (info) + `anchor` on **this** host |
| `GET /files/:id/description-links` | Description links whose **source object lives in that file** (peer = target info) |
| `PUT /objects/:id/tags` | Replace object tags |
| `PATCH /tags/:id` | Update tag name/color/icon |
| `PATCH /objects/:id` | `sort_key`, `anchor`, image/table `payload`, and `diagram_x` / `diagram_y` |

Object GET / file object list payloads include `tags[]` and `connections[]` (undirected related + description rows with a `peer` summary). Deleting an object or file removes links where it is source **or** target.

## Image and table payloads

| Type | Typical payload |
|------|-----------------|
| `image` | `{ "url", "path", "width", "caption" }` |
| `table` | `{ "rows": [[{ "text" }], …], "chart"?: { "enabled", "chartType", "colors" } }` |

Chart tables use the same `table` type; agent text still expands them as `[GRAPH id chartType=…]` with two TSV rows (+ optional colors). New charts start with empty cells. Normalize helpers: [`services/table_payload.py`](services/table_payload.py). Spec: production agent system prompt.

**Naming:** “object graph” = info **links map** (`GET /objects/graph`). “Chart table” / `[GRAPH]` pointer = visualization quality on a table object.

## Deletion

Deleting anything that contains objects must cascade, or the database keeps orphans that still appear in agent text **and on the objects map**.

`services/delete_cascade.py` owns cascades for task, object embed, file, topic, view, tag, workspace, and automation. Route handlers must call it rather than deleting rows directly.

**File body is authoritative for membership.** When `PATCH /files/:id` changes `document_json`, `purge_unreferenced_embeds_for_file` cascade-deletes every `objects` row for that file whose pointer is no longer in the marker text (covers Super Editor selection delete/cut that never called `DELETE /objects/:id`).

## Modules

| Module | Role |
|--------|------|
| [`routes/objects.py`](routes/objects.py) | Create/update/delete embeds; links; graph; object tags; insert embed blocks |
| [`services/object_graph.py`](services/object_graph.py) | Links-map build, connection dicts, link/tag helpers |
| [`services/table_payload.py`](services/table_payload.py) | Normalize table/chart payloads (incl. legacy graph shape) |
| [`routes/tasks.py`](routes/tasks.py) | Task CRUD, status, due date |
| [`routes/task_lists.py`](routes/task_lists.py) | Task list contents and reorder |
| [`routes/information.py`](routes/information.py) | Info pieces |
| [`routes/views.py`](routes/views.py) | Views and memberships |
| [`services/task_list_order.py`](services/task_list_order.py) | Canonical ordering within a list |
| [`services/task_ops.py`](services/task_ops.py) | Toggle / unmark without a request — used by automations and by the HTTP routes |
| [`services/delete_cascade.py`](services/delete_cascade.py) | Cascade rules for every container |

## Rules

- A task exists once. Views reference it; they never copy it.
- Topic types are not tags. Tags stay on objects (and leftover topic tag rows). Classification lives in `topic_types`.
- Ordering is explicit (`list_order_index`), never implied by id.
- Creating an object via `POST /files/:id/objects` must also insert its embed block — an object with no block is invisible.
- Never delete a container without its cascade.
- Related links are info ↔ info only. Description links are host object → info (any host type).
