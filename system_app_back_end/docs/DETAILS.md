# Details blocks

Topic-scoped reusable text as `blocks.type = "details"`. Frontend spec: [`../../system_app_front_end/lib/features/blocks/DETAILS.md`](../../system_app_front_end/lib/features/blocks/DETAILS.md).

## Schema

Block content:

```json
{ "title": "string", "text": "string", "spans": [] }
```

Task attachment (migration **017**):

```sql
tasks.details_block_id → blocks.id ON DELETE SET NULL
```

## API

| Method | Path | Description |
|--------|------|-------------|
| GET | `/topics/<topic_id>/details-blocks` | List details blocks in topic |
| PATCH | `/tasks/<id>` | Set `details_block_id` (null to detach) |

## Services

| Module | Role |
|--------|------|
| [`services/details_lookup.py`](../services/details_lookup.py) | Topic index, validation, title match suggest |
| [`services/ai_interactive/upload_details.py`](../services/ai_interactive/upload_details.py) | AI copy flow |
| [`services/ai_interactive/details_router.py`](../services/ai_interactive/details_router.py) | Pick block within topic |

## AI tool

`POST /ai/run` with `{ "tool": "upload_details", "topic_id", "context": { "text" } }` → `{ "action": "insert", "result": "..." }`.

## Tests

- [`tests/test_details_lookup.py`](../tests/test_details_lookup.py)
- [`tests/test_task_details_block.py`](../tests/test_task_details_block.py)
