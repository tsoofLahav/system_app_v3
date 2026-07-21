# Tasks — persistence and ordering

Backend reference for task rows, list order, view order, move/reorder APIs, and delete cascade. Frontend behavior: [`../../system_app_front_end/lib/features/tasks/TASK_FILES.md`](../../system_app_front_end/lib/features/tasks/TASK_FILES.md).

## Schema

### `tasks`

| Column | Role |
|--------|------|
| `block_id` | Owning `task_list` block |
| `list_order_index` | Order within list (active zone then done). Added in migration **016**. |
| `status` | `active` or `done` |
| `title`, `due_date`, … | Standard task fields |

Sort for `GET /blocks/:id/tasks`:

```sql
ORDER BY CASE WHEN status = 'done' THEN 1 ELSE 0 END,
         list_order_index,
         id
```

### `task_views`

One primary membership per task (migration **015**). Relevant fields:

| Column | Role |
|--------|------|
| `view_type` | e.g. `weekly`, `tasks`, … |
| `order_index` | Order within a view group (flip assigned groups, view panes) |
| `section_name`, `topic_key`, … | View pane grouping |

### `files.settings`

| Key | Role |
|-----|------|
| `tasks_flip_by_view` | When true, frontend groups tasks file by view assignment |

### Row blocks

`task` blocks (`content.task_id`) live in the file layout. **Backend does not reorder them on drag.** Create/delete row blocks is a frontend concern.

## Services

| Module | Role |
|--------|------|
| [`services/task_list_order.py`](../services/task_list_order.py) | `list_order_index` read/write, zone insert merge, cross-list move |
| [`services/task_view_order.py`](../services/task_view_order.py) | Bulk `task_views.order_index` update |
| [`services/task_view_assign.py`](../services/task_view_assign.py) | Assign / change view membership |
| [`services/delete_cascade.py`](../services/delete_cascade.py) | Task and file delete side effects |

### `task_list_order.py`

| Function | Role |
|----------|------|
| `tasks_for_list_block` | Query tasks for a list, sorted |
| `apply_list_task_order` | Set `list_order_index` 0..n-1 from id list |
| `reorder_tasks_in_list_block` | Validate + apply order for one list |
| `move_task_to_list_block` | Change `block_id`, status zone, reindex source + target |
| `merged_task_ids_after_zone_insert` | Build merged active+done id list after insert |
| `next_list_order_index` | Append helper for new tasks |

### `task_view_order.py`

`reorder_task_views(view_type, ordered_task_ids, section_name=None)` — looks up membership **per task_id + view_type**. When `section_name` is omitted, do not filter by section (required for flip same-view reorder with sectioned tasks).

### `delete_cascade.py`

`delete_task_cascade(task_id)`:

1. Normalize `tasks.block_id` to owning `task_list` if needed
2. Delete automation companions and `task_views` for the task
3. Delete the task row
4. Compact `list_order_index` on the owning list

**Does not** delete `task` row blocks — frontend `deleteTaskInFile` calls `DELETE /blocks/:id` separately.

## Routes

### Tasks ([`routes/tasks.py`](../routes/tasks.py))

| Method | Path | Body | Effect |
|--------|------|------|--------|
| GET | `/blocks/:block_id/tasks` | — | List tasks sorted by status → `list_order_index` → `id` |
| POST | `/tasks` | `{ block_id, title, status, … }` | Create; sets `list_order_index` via `next_list_order_index` |
| PATCH | `/tasks/:id` | partial fields incl. `list_order_index` | Update task |
| DELETE | `/tasks/:id` | — | `delete_task_cascade` |
| POST | `/blocks/:block_id/tasks/reorder` | `{ "task_ids": [1,2,3] }` | Bulk list order (active then done sequence) |
| POST | `/blocks/:block_id/tasks/move` | `{ "task_id", "insert_index", "target_done" }` | Move to list + zone |
| PUT | `/tasks/:id/view` | `{ "view_type", "order_index", … }` | Assign view |

**Import requirement:** `delete_task_cascade` must be imported in `routes/tasks.py`. Missing import causes 500 on delete.

### Task views ([`routes/task_views.py`](../routes/task_views.py))

| Method | Path | Body | Effect |
|--------|------|------|--------|
| POST | `/task_views/reorder` | `{ "view_type", "task_ids", "section_name?" }` | Bulk view order |

## Migrations

| File | Change |
|------|--------|
| `015_task_single_view_and_file_settings.sql` | Single view per task; file settings |
| `016_tasks_list_order_index.sql` | Add `list_order_index`, backfill from row block order |

Apply **016** manually on production DB before relying on list reorder.

## Tests

| File | Covers |
|------|--------|
| [`tests/test_task_list_order.py`](../tests/test_task_list_order.py) | Reorder, move, zone insert |
| [`tests/test_task_view_order.py`](../tests/test_task_view_order.py) | View reorder |
| [`tests/test_delete_task_cascade.py`](../tests/test_delete_task_cascade.py) | Cascade + compact |
| [`tests/test_task_view_assign.py`](../tests/test_task_view_assign.py) | View assignment |

## Extension rules

1. New order semantics → extend `task_list_order` or `task_view_order`, add route, mirror in Flutter `TaskService`.
2. Keep sort order in GET endpoints aligned with frontend `orderedTasksForListBlock` / `_orderedTasksInView`.
3. Do not move row blocks in backend reorder endpoints.
4. When changing delete behavior, preserve frontend contract: server deletes task + views; client deletes row block.
