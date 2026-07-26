# Tasks — persistence and ordering (v2)

Backend reference for task rows inside **task_list objects**. Frontend: [`../../system_app_front_end/lib/features/document/README.md`](../../system_app_front_end/lib/features/document/README.md).

## Schema

### `task_lists`

Minimal container referenced by `objects.task_list_id`.

### `tasks`

| Column | Role |
|--------|------|
| `task_list_id` | Owning task list object |
| `list_order_index` | Order within list (active zone, then done) |
| `status` | `active` or `done` |
| `title`, `due_date`, … | Standard task fields |

Sort order:

```sql
ORDER BY CASE WHEN status = 'done' THEN 1 ELSE 0 END,
         list_order_index,
         id
```

### `view_task_memberships`

View membership per task (views act like tags/contexts). Same task, same done state everywhere.

## Services

| Module | Role |
|--------|------|
| [`services/task_list_order.py`](../services/task_list_order.py) | `list_order_index`, reorder, cross-list move |
| [`services/delete_cascade.py`](../services/delete_cascade.py) | Task / object / file delete side effects |

## Routes

See [`API.md`](API.md) — `/task-lists/...`, `/tasks/.../memberships`.

## Tests

| File | Covers |
|------|--------|
| [`tests/test_task_list_order.py`](../tests/test_task_list_order.py) | Zone insert merge |
| [`tests/test_document_body.py`](../tests/test_document_body.py) | JSON document codec |
