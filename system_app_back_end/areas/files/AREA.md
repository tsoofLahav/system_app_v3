# Area: File structure & functionality (backend)

Owns how a file's content is **modeled, stored, and converted**. Frontend counterpart: [`system_app_front_end/lib/areas/files/AREA.md`](../../../system_app_front_end/lib/areas/files/AREA.md).

## Core rule

A file is **one continuous document**. The user should feel a single flowing text — paragraphs, lists, tables, and embedded objects are all part of the same body, not separate widgets stacked together.

Everything the user sees in a file is stored in **one column**: `files.document_json`.

## Storage

| Column | Meaning |
|--------|---------|
| `document_json` | The whole document as a v3 block tree (JSON text) |
| `name`, `topic_id`, `order_index` | Placement inside a topic |
| `meta` (JSONB) | Automation anchors and misc flags |
| `archived_at` | Soft archive |

**There is no plain-text column.** Plain text is always derived, never stored.

## Which files a topic shows

`topics.file_layout` holds the layout the user picked. The layout has a fixed number of slots — `single` 1, `split` 2, `hero_left` and `hero_right` 3, `row` and `grid` all of them — and files fill those slots in `order_index` order.

A file past the last slot is **not on screen**. It is not archived and not marked; it is simply further down the order than the layout has room for, and the user reaches it by rearranging the topic.

This is why there is no flag on the file. Prominence is a property of the topic's arrangement, so the only thing the backend stores is the order and the layout. `files.is_essence` existed for this and was dropped in [`migrations/004_topic_file_layout.sql`](../../migrations/004_topic_file_layout.sql); ordering already carried the same information, since arranging always wrote the shown files first.

## Block tree (v3)

```json
{
  "version": 3,
  "blocks": [
    { "id": "b1", "type": "paragraph", "text": "…", "spans": [] },
    { "id": "b2", "type": "heading", "level": 2, "text": "Goals", "spans": [] },
    { "id": "b3", "type": "bullet_list", "items": [{ "id": "li1", "text": "…", "indent": 0 }] },
    { "id": "b4", "type": "table", "rows": [[{ "text": "A" }, { "text": "B" }]] },
    { "id": "b5", "type": "embed", "object_id": 42 }
  ]
}
```

- Order is **array order** — there are no character offsets between blocks.
- `spans` carry inline formatting (bold, italic, underline, size, color) as ranges on `text`.
- Legacy `list` + `list_style` normalizes to `bullet_list` / `ordered_list` on read.
- Reads accept v1/v2 shapes and migrate; **writes always normalize to v3**.
- Extra blank lines usually live as `\n\n` **inside** a paragraph’s `text` (the editor coalesces adjacent paragraphs with `\n`, so a visible blank line is `\n\n` in that string). The agent-text mapper turns each such gap into `[SPACER n="…"]` and back into empty paragraphs (no editor `spacer` type). Legacy `type: "spacer"` blocks normalize to empty paragraphs.

### Lists and tables

Lists and tables are **nodes inside the document**, not separate database rows. They are part of the text flow: pressing Enter on an empty list item or empty table row ends that structure and continues as a paragraph, so the user never feels they left the document.

Table cells hold `{ text, spans }`. Rows are padded to a uniform column count on read.

### How objects fit in

An **embed** block is a pointer: `{ "type": "embed", "object_id": 42 }`. The content lives in the `objects` table ([objects area](../objects/AREA.md)).

The document owns **where** an object sits; the objects area owns **what** it contains (data, views, links). In-file presentation (caret, menus, embed widgets) is frontend **files**.

| Rule | Meaning |
|------|---------|
| Top-level only | Embeds are siblings of paragraphs, lists, and tables — never nested inside a list or table |
| Array order is position | No character offsets between blocks |
| Delete cascades | Removing an embed must go through the objects cascade so the object row (and tasks, info, …) are cleaned up |

Creating via `POST /files/:id/objects` inserts the embed block at `block_index` in the same transaction.

Empty-final Enter exit (task / info / graph continuing as a paragraph below the object) is a **frontend document edit** — it does not change object rows, only inserts a paragraph after the embed in `document_json`.

## Two representations of the same file

| Representation | Where | Used for |
|----------------|-------|----------|
| **Full version** — block tree | `files.document_json` | The editor, persistence, source of truth |
| **Text version** — agent text | Computed on demand | AI reading/writing, search, diffs |

The text version flattens the tree into deterministic plain text with fenced regions (`[TABLE]`, `[BULLET_LIST]`, `[SPACER]`, `[TASK_LIST id="…"]`, `[INFO]`, `[IMAGE]`, `[GRAPH]`). Embedded object content is expanded inline so the agent sees real content, not ids alone.

Frozen shapes (see production agent prompt):

| Fence | Shape |
|-------|--------|
| `SPACER` | Extra blank lines ↔ empty paragraphs / blank runs in paragraph text |
| `TASK_LIST` | ACTIVE/DONE checkbox lines |
| `INFO` | First line title, remaining body |
| `IMAGE` | Single-line `caption` + optional `url` |
| `GRAPH` | Optional `chartType`; labels / values / optional colors as tab rows |

It is **never persisted**. Converting back (`apply_agent_text`) rebuilds a block tree and rejects any result that would silently drop an existing embed.

Format spec: [`content/production_agent/system_prompt.md`](../../../content/production_agent/system_prompt.md)

## Modules

| Module | Role |
|--------|------|
| [`services/document_v3.py`](services/document_v3.py) | Parse, normalize, serialize, migrate the block tree |
| [`services/document_agent_text.py`](services/document_agent_text.py) | Block tree ↔ agent text |
| [`services/document_body.py`](services/document_body.py) | Back-compat re-exports |
| [`services/document_promote.py`](services/document_promote.py) | Promote legacy inline embeds to object rows |
| [`services/file_versions.py`](services/file_versions.py) | Snapshot before agent/automation writes |
| [`routes/files.py`](routes/files.py) | File CRUD |
| [`routes/file_versions.py`](routes/file_versions.py) | History and `POST /files/:id/diff` |
| [`routes/topics.py`](routes/topics.py) | Topics — the container files live in |

## Sending documents to the app

`File.to_dict()` includes `document_json` unless a caller opts out, and the file lists the app reads from **must not** opt out. The topic screen renders every file of a topic inline from one `GET /topics/:id/files` response; there is no second request per file.

Leaving the document out of that response is a data-loss bug, not a display one: each editor opens empty, and the first keystroke saves that emptiness over the stored document. `tests/files/test_file_routes_document.py` guards it.

`include_document=False` is for callers that only want names — currently the agent's file listing, so a tool call does not pour every document into the prompt.

## Rules

- Never write a document body that is not valid v3 — always go through `serialize_document`.
- Never store derived plain text.
- Never drop an embed block during a programmatic edit; fail loudly instead.
- Save a file version before any agent or automation write.
- Any endpoint the editor loads a file from must include `document_json`.

## Known gaps

Agent text round-trip is not yet lossless. Open issues, worst first:

| Gap | Effect |
|-----|--------|
| `direct_apply` writes `file.document_json` before `apply_object_updates` runs, and `run_agent` commits without checking tool errors | A failed object update can still persist the new document |
| Legacy embeds (`object_id` null) serialize to markers the parser cannot read, and the agent path never calls `promote_legacy_embeds` | Those blocks are dropped on apply |
| `_escape_cell` escapes `\` and `\t` but not `\n` | A newline in a table cell becomes an extra row on read |
| Unmatched fence markers in plain text advance one char without emitting it | Text like `Hello [TABLE] world` loses characters |
| `_sync_task_list` archives every task and inserts new rows | Task ids churn on each apply; `view_task_memberships` point at archived tasks |
| Malformed list/task lines are skipped with `continue` | Items vanish with no error |
| Spans are dropped on parse (by design) | Any agent edit clears inline formatting across the whole file |

Tests cover happy paths only — no coverage for ordered-list round-trip, nested lists, newlines in cells, legacy or duplicate embeds, or `direct_apply` rollback.
