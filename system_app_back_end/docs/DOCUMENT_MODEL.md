# Document model (v3 block tree)

Files store a JSON **document** in `files.document_json`. Version 3 uses an ordered block array with embed references.

**Related docs**

- Agent text serialize/parse: [`PRODUCTION_AGENT.md`](PRODUCTION_AGENT.md)
- In-app editor UX: [`../../system_app_front_end/docs/APP_FILES.md`](../../system_app_front_end/docs/APP_FILES.md)

## Shape

```json
{
  "version": 3,
  "blocks": [
    { "id": "b1", "type": "paragraph", "text": "Morning notes", "spans": [] },
    { "id": "b2", "type": "heading", "level": 2, "text": "Goals", "spans": [] },
    {
      "id": "b3",
      "type": "bullet_list",
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
| `bullet_list` | Inline list items (`ordered_list` for numbered) |
| `table` | Rows of cells with text and spans |
| `embed` | Reference to `objects.id` |

Legacy `list` + `list_style` normalizes to `bullet_list` / `ordered_list` on read.

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

See [`PRODUCTION_AGENT.md`](PRODUCTION_AGENT.md). Summary:

- `document_to_agent_text()` — tree → plain agent text (on demand only)
- `apply_agent_text()` — agent text → tree; validates embed ids are preserved
