# Document body model (v2 inline)

Files store a JSON **document body** in `files.body`. Version 2 uses a single text stream with overlays.

## Shape

```json
{
  "version": 2,
  "text": "Goals\n• Item one\n\uFFFC\nMore notes",
  "spans": [{"start": 0, "end": 5, "bold": true}],
  "regions": [
    {"id": "r1", "kind": "list", "start": 6, "end": 16, "list_style": "bullet"},
    {"id": "r2", "kind": "table", "start": 20, "end": 30, "rows": [["A", "B"]]}
  ],
  "embeds": [
    {"id": "e1", "kind": "object", "object_type": "task_list", "object_id": 42, "offset": 17},
    {"id": "e2", "kind": "image", "offset": 18, "url": "https://…"},
    {"id": "e3", "kind": "graph", "offset": 19, "labels": ["A"], "values": [1]},
    {"id": "e4", "kind": "object", "object_type": "info", "object_id": 99, "offset": 20}
  ]
}
```

## Fields

| Field | Purpose |
|-------|---------|
| `text` | Single source of truth for editable content |
| `spans` | Character-range formatting (`bold`, `italic`, `underline`, `size`) |
| `regions` | List/table ranges `[start, end)` styled in the editor; moved via cut/copy/paste only |
| `embeds` | Graph, image, task_list, info anchored at `offset` |

Each embed occupies one character slot in `text`: U+FFFC (object replacement character).

## Migration

- Plain text with `{{task:id}}` / `{{info:id}}` markers → v2
- v1 `nodes[]` JSON → v2 via `migrate_v1_nodes_to_v2`
- Reads accept v1; writes normalize to v2

## Object embeds

`object_id` references `objects.id` (API: `/objects/:id`). Task list and info payloads live in related tables; the document only stores the anchor offset.

Creating an object via `POST /files/:id/objects` accepts `{ "type", "offset" }` and inserts `\uFFFC` + embed entry server-side.

## Agent plain text

`document_plain_text()` flattens v2 bodies for diffs: text with embed chars as spaces, plus `[task_list #N]` / `[info #N]` lines.
