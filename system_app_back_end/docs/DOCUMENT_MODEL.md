# Document model (v3 block tree)

Files store a JSON **document** in `files.document_json`. Version 3 uses an ordered block array with embed references.

## Shape

```json
{
  "version": 3,
  "blocks": [
    { "id": "b1", "type": "paragraph", "text": "Morning notes", "spans": [] },
    { "id": "b2", "type": "heading", "level": 2, "text": "Goals", "spans": [] },
    {
      "id": "b3",
      "type": "list",
      "list_style": "bullet",
      "items": [{ "id": "li1", "text": "Item one", "indent": 0, "spans": [] }]
    },
    {
      "id": "b4",
      "type": "table",
      "rows": [[{ "text": "A", "spans": [] }, { "text": "B", "spans": [] }]]
    },
    { "id": "b5", "type": "embed", "object_id": 42 }
  ]
}
```

## Block types

| Type | Purpose |
|------|---------|
| `paragraph` | Rich text with optional spans |
| `heading` | Heading level 1–6 with spans |
| `list` | Inline list items with indent and spans |
| `table` | Editable table cells with spans |
| `embed` | Reference to `objects.id` |

Position is **array order** — no character offsets.

## Object embeds

Supported object types in `objects` table:

| Type | Storage |
|------|---------|
| `task_list` | `task_lists` + `tasks` |
| `info` | `information_pieces` |
| `image` | `objects.payload` (`url`, `width`, …) |
| `graph` | `objects.payload` (`labels`, `values`, …) |

Creating an object via `POST /files/:id/objects` accepts `{ "type", "block_index" }` and inserts an embed block server-side.

## Migration

- Plain text with `{{task:id}}` / `{{info:id}}` → v3
- v1 `nodes[]` JSON → v3
- v2 inline `{ text, spans, regions, embeds }` → v3 on read
- Writes always normalize to v3

## Agent text

`document_to_agent_text()` produces deterministic sections:

```
[TASK_LIST id="42"]
ACTIVE:
- [ ] Call clinic
[/TASK_LIST]

[INFO id="17"]
Body text
[/INFO]
```

Malformed agent input must not silently delete existing objects (`apply_agent_text` validation).
