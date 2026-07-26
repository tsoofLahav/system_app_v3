# Document model (v2 rich files)

## Encoding: JSON document in `files.body`

Each file body is a JSON string:

```json
{
  "version": 1,
  "nodes": [
    {"id": "n1", "type": "paragraph", "text": "Hello", "spans": []},
    {"id": "n2", "type": "table", "rows": [["A", "B"]]},
    {"id": "n3", "type": "list", "list_style": "bullet", "items": ["One"]},
    {"id": "n4", "type": "image", "url": "https://…"},
    {"id": "n5", "type": "graph", "labels": ["Mon"], "values": [1.0]},
    {"id": "n6", "type": "object", "object_type": "task_list", "object_id": 42},
    {"id": "n7", "type": "object", "object_type": "info", "object_id": 99}
  ]
}
```

### Node types

| Type | DB object? | Notes |
|------|------------|-------|
| `paragraph` | No | Rich text: `text` + `spans[]` (bold, italic, underline, size) |
| `table` | No | `rows: [[cell, …], …]` |
| `list` | No | `items: [string]` + `list_style` (`bullet` \| `numbered`) |
| `image` | No | `url`, optional `width` |
| `graph` | No | `labels`, `values` |
| `object` | Yes | `object_type`: `task_list` \| `info`; `object_id` = `objects.id` |

Embed placement is **document-flow** (Notion-style nodes between paragraphs), not mid-word inline runs.

### Object anchoring

`objects.anchor` stores the document node reference:

```json
{"kind": "node", "node_id": "n6", "index": 3}
```

`object_id` in the document always refers to the **`objects` table primary key**, not the underlying entity id.

### Task lists

- `objects.type = task_list` → `task_lists` row → ordered `tasks` via `tasks.task_list_id` + `list_order_index`
- Task `status` (active/done) is global; toggling in any view updates the task everywhere
- View membership via `view_task_memberships` (views act like tags/contexts)

### Info objects

- `objects.type = info` → `information_pieces` row (title, body, metadata.spans)
- Framed paragraph in the editor
- Links to other entities via `links` (`source_type=info`)

### Agent / diff

- Agents read/write the full JSON body string
- Review UI uses `document_plain_text()` ([`services/document_body.py`](../services/document_body.py)) for readable diffs
- Legacy plain-text bodies (including `{{info:id}}` markers) migrate on parse

### Versioning

Every applied write saves `file_versions.body` before updating `files.body`.
