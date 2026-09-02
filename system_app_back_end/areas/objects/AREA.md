# Area: Objects (backend)

Frontend counterpart: [`system_app_front_end/lib/areas/objects/AREA.md`](../../../system_app_front_end/lib/areas/objects/AREA.md).

## What an object is

An object is a **piece of information with special qualities** — something that behaves differently from plain text because it can be tracked, toggled, ordered, filtered, or linked.

Plain sentences live in the document body. Anything the system needs to *reason about* becomes an object.

Objects live in the `objects` table and appear inside a file through an `embed` block that points at `objects.id`. The [files area](../files/AREA.md) owns **placement and in-file presentation**; this area owns **content, type logic** (tasks/views, info links), and cascades.

| Type | Backing storage | Special quality |
|------|-----------------|-----------------|
| `task_list` | `task_lists` + `tasks` | Ordering, active/done/inactive/pending, views |
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

**Order.** Every task carries `list_order_index` within its `task_list`. Users reorder freely; order is explicit, not derived from creation time. Reordering rewrites indices for the whole list so they stay dense (`active` ids then `done` ids). Views keep **two** membership orders: `order_index` for section mode and `topic_order_index` for topic mode (`view_task_memberships`). List order, view-by-section, and view-by-topic are independent.

**Done / active / inactive / pending.** `tasks.status` is `active`, `done`, `inactive`, or `pending`. A task exists **once**. Marking it done anywhere updates the single row and is reflected everywhere it appears. List queries and the UI show Active then Done zones; inactive and pending sit with Active. `POST /tasks/:id/move` can place a task into a zone (including the same list) without wiping pending/inactive when the drop stays in the non-done zone.

A task **without a view is inactive** (grey filled mark, not toggleable) until it is assigned one — file-list creates default to `inactive`; view-frame creates default to `active`. Assigning a view turns inactive → active; removing the view turns active/pending → inactive (`done` stays done). **Pending** requires a view: the membership is kept, `due_date` is the activate-on day, and the task is hidden on the view page until then. The minute cron calls `activate_due_pending_tasks` (date ≤ today in `Asia/Jerusalem`) so pending becomes active without a user automation. Toggle is a no-op for inactive and pending.

**Empty titles.** `POST /task-lists/:id/tasks` accepts `title: ""` (blank row). Only a missing title key may default; never coerce empty string to `"New task"`.

**Section cadence and windows.** `views.layout_config.sections[]` may include `key` (stable), `cadence` (`routine` / `one_time`), and `default` (at most one section). PATCH of `layout_config` backfills keys and creates matching `section_window` automations (automations area). Complimentary tasks (`tasks.source_automation_id`, `complimentary_role`) are marked by the pipeline when the work finishes; the checkbox still toggles like any other task (giving up that round). Only the roles the automation needs are stored.

**Views.** A view is a user-made list that a task can appear in without being copied. Membership lives in `view_task_memberships`, with its own ordering per view **and per display mode**. **Product rule: a task belongs to at most one view at a time** (the client replaces memberships rather than stacking them). Agent `[TASK_LIST]` writes update those same `tasks` rows (title/status); memberships stay because the id does not change. A removed checkbox line is `delete_task_cascade` — membership and that task's description links go with it. Soft-archive is not how apply removes a task, and those rows are not what the Archive page shows. Section definitions (including optional `default: true` on one section), display mode (`by_section` / `by_topic`), and topic-frame order live in `views.layout_config` (JSON) — not separate tables. Memberships still carry `section_name` / `section_flag` for which section a task sits in, plus `order_index` (section mode) and `topic_order_index` (topic mode). Assigning a view from a task that already has a home topic should store that topic on the membership (`topic_key`); an empty key is **No topic** only for tasks created in a view frame with no topic. Topic/list placement on the client lists that topic’s task-list objects via `GET /topics/:id/task-lists` (live files only) and does not rewrite view or section.

```
tasks ──< view_task_memberships >── views
                              layout_config: sections, display_mode, topic_order
```

Views are membership and filtering only. **Never add per-view status columns** — that would duplicate task state. `DELETE /views/:id` drops memberships and the view row; tasks stay. `views.order_index` is the sidebar list order.

**Membership GET enrichment.** Listing memberships includes the nested task plus home-topic fields (`topic_id`, `topic_name`, `topic_key`, `topic_color`) so the frontend can colour topic frames without extra round-trips.

**Create task in a view.** `POST /views/:id/tasks` creates a real `tasks` row with **`task_list_id` null by default** (orphan — no home list). Optional `task_list_id` places it into an existing list. Membership takes **only the frame it was added in**: `section_name` / `section_flag` / `topic_key` from that request (empty/null = Uncategorized / No topic). `after_task_id` is insert order only — do not copy the sibling’s section, topic, or home list. `tasks.task_list_id` is already nullable. Deleting a task with a home list should warn; orphans need no “original list” warning.

**Task list header.** `task_lists.title` (migration `005`) is the list’s header — same role as info title. `PATCH /task-lists/:id` updates it. Membership/task payloads include `task_list_title` when the task has a home list. Agent text carries it as `title="…"` on `[TASK_LIST id="…"]` so `patch_file` can rename the list.

## Information and the object graph

An `info` object holds a piece of knowledge (`title`, `body`, `metadata`). The file UI edits them as one text field (first line → `title`); storage and agent text stay title + body. Graph node titles are the stored title — empty stays empty (the map paints a fallback; Connect info hides unnamed infos). Do not coerce empty titles to `"Info"`.

The `links` table is the workspace **object graph**, keyed by **`objects.id`** for object endpoints (migration `006` also adds `links.kind`, `links.anchor`, `tags.icon`).

| Column | Meaning |
|--------|---------|
| `source_type`, `source_id` | Host: an object (`info` / `task_list` / `table` / …) or a **task** (`source_type='task'`, `source_id=tasks.id`). Related: one info. |
| `target_type`, `target_id` | Related: the other info. Description: the connected info. |
| `kind` | `related` (default) or `description` |
| `anchor` | Description span on the **host**: `{ segment_id, start, end }` (`file_id` optional) |

| Kind | Shape | How it is created |
|------|-------|-------------------|
| **Related** | **info ↔ info** only | Object chrome or map node → Add connection |
| **Description** | **Marked text → an info** | Field menu → Connect info… On a **task title**, stored on the task (`source_type=task`, `anchor.segment_id` = `task:{id}`) so the underline stays with that task. On other objects, stored on the host object. Many spans per host are allowed. Self-links are rejected. |

Description and related stay separate. Text inside an info does **not** create a map edge; chrome **Add connection…** (or `action=related`) does. Deleting one kind does **not** delete the other.

Task title description links travel with the task row (`description_links` on task payloads and view memberships). `GET /files/:id/description-links` also returns task-hosted links whose home list lives in that file, so in-file underlines keep working. Older `task_list` + `#t{index}` links still paint only if looked up by that slot — new Connect info uses `task:{id}`. `delete_task_cascade` drops those rows. Agent edits of a fence update that same host (`_sync_info` / `_sync_task_list` / table payload merge) and leave related + description links on its id. Description **anchors** (`start`/`end`) remap with the same prefix/suffix diff as user typing, so inserting text before a connected span moves the underline with those glyphs. Dropping the pointer (or a task checkbox line) is what cascade-deletes the object and its connections.

| Endpoint | Role |
|----------|------|
| `GET /objects/graph?workspace_id=` | Info nodes (title, body, topic_id/color, tag_ids, `diagram_x`/`diagram_y`) + related info↔info edges for the objects map (description edges skipped) |
| `PUT /objects/graph/positions` | Batch-write map coordinates `{ workspace_id, positions: [{ object_id, x, y }] }` |
| `GET/POST /objects/:id/links` | List / create connections. Related: `target_object_id` (info). Description: `target_object_id` (info) + `anchor` on **this** host |
| `PATCH /objects/:id/links/:link_id` | Description only: new `anchor` (start/end move with the host text) |
| `POST /tasks/:id/links` | Description only: `target_object_id` (info) + `anchor` on **this** task title. `PATCH/DELETE /tasks/:id/links/:link_id` |
| `GET /files/:id/description-links` | Description links whose **source object or task** lives in that file (peer = target info) |
| `PUT /objects/:id/tags` | Replace object tags |
| `PATCH /tags/:id` | Update tag name/color/icon |
| `PATCH /objects/:id` | `sort_key`, `anchor`, image/table/**info** `payload` (info uses this for `look`), and `diagram_x` / `diagram_y` |

Object GET / file object list payloads include `tags[]` and `connections[]` (undirected related + description rows with a `peer` summary). Deleting an object or file removes links where it is source **or** target.

## Image and table payloads

| Type | Typical payload |
|------|-----------------|
| `image` | `{ "url", "path", "width", "caption", "look"? }` — `width` is 0–1 of the file pane (full = `1`); the picture keeps its aspect ratio. `look`: `none` (default) / `frame` / `greyscale` / `frame_greyscale`. Adjacent pictures can merge into `{ "images": [{url, caption}, …] }` with the first pane also mirrored on `url` / `caption` so older readers still see one picture |
| `table` | `{ "rows": [[{ "text" }], …], "chart"?: { "enabled", "chartType", "colors" }, "look"? }` — `look`: `grid` (default) / `open` / `lined`. Normalize keeps `look`. |
| `info` | Title/body on `information_pieces`. Optional `objects.payload.look`: `card` (default) / `plain` / `ruled` |

Omitted `look` means the current (default) chrome. No migration. Task lists have no look.

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
| [`services/description_anchor_remap.py`](services/description_anchor_remap.py) | Shift description `start`/`end` when host text changes (agent apply) |
| [`services/table_payload.py`](services/table_payload.py) | Normalize table/chart payloads (incl. legacy graph shape) |
| [`services/image_payload.py`](services/image_payload.py) | One picture or a row of panes (`images[]`, first mirrored on `url`) |
| [`routes/tasks.py`](routes/tasks.py) | Task CRUD, status, due date, task description links |
| [`routes/task_lists.py`](routes/task_lists.py) | Task list contents and reorder |
| [`routes/information.py`](routes/information.py) | Info pieces |
| [`routes/views.py`](routes/views.py) | Views and memberships |
| [`services/task_list_order.py`](services/task_list_order.py) | Canonical ordering within a list |
| [`services/task_ops.py`](services/task_ops.py) | Toggle / unmark / pending → active — used by automations, cron, and HTTP routes |
| [`services/delete_cascade.py`](services/delete_cascade.py) | Cascade rules for every container |

## Rules

- A task exists once. Views reference it; they never copy it. Agent `[TASK_LIST]` apply updates those rows in place.
- Topic types are not tags. Tags stay on objects (and leftover topic tag rows). Classification lives in `topic_types`.
- Ordering is explicit (`list_order_index`), never implied by id.
- Creating an object via `POST /files/:id/objects` must also insert its embed block — an object with no block is invisible.
- Never delete a container without its cascade.
- Related links are info ↔ info only. Description links are host object → info (any host type), or **task → info** for a title span. Agent edits of a host update that row, remap description anchors with the text, and leave the links; deleting the host (or a task checkbox line) is what cascade-removes them.
