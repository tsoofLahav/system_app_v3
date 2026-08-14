# Area: File structure & functionality (backend)

Owns how a file's content is **modeled, stored, and converted**. Frontend counterpart: [`system_app_front_end/lib/areas/files/AREA.md`](../../../system_app_front_end/lib/areas/files/AREA.md).

## Core rule

A file is **one continuous document**. The user should feel a single flowing text — paragraphs, lists, tables, and embedded objects are all part of the same body, not separate widgets stacked together.

Everything the user sees in a file is stored in **one column**: `files.document_json`.

## Storage

| Column | Meaning |
|--------|---------|
| `document_json` | **Editor text (v4)** — marker string with header `%%system_app_document v4` (column name kept for now) |
| `name`, `topic_id`, `order_index` | Placement inside a topic |
| `meta` (JSONB) | Automation anchors and misc flags |
| `archived_at` | Soft archive |

Legacy **v3 JSON** in this column is migrated to editor text on read (`File.to_dict`) and rewritten on the next save. **Spans are dropped** on migrate (span encoding is a follow-up). Spec: frontend [`DOCUMENT_TEXT.md`](../../../system_app_front_end/lib/areas/files/editor/DOCUMENT_TEXT.md).

## Which files a topic shows

`topics.file_layout` holds the layout the user picked. The layout has a fixed number of slots — `single` 1, `split` 2, `hero_left` and `hero_right` 3, `row` and `grid` all of them — and files fill those slots in `order_index` order.

A file past the last slot is **not on screen**. It is not archived and not marked; it is simply further down the order than the layout has room for, and the user reaches it by rearranging the topic.

This is why there is no flag on the file. Prominence is a property of the topic's arrangement, so the only thing the backend stores is the order and the layout. `files.is_essence` existed for this and was dropped in [`migrations/004_topic_file_layout.sql`](../../migrations/004_topic_file_layout.sql); ordering already carried the same information, since arranging always wrote the shown files first.

## Editor text (v4 — source of truth)

Stored body starts with `%%system_app_document v4`, then marker text:

```text
%%system_app_document v4
Hello
world

[INFO id="42"]

[BULLET_LIST]
- point 1
[/BULLET_LIST]
```

- Blocks separated by `\n\n`; soft break inside a paragraph = `\n`.
- Gaps: `[SPACER]` / `[SPACER n="N"]`.
- Objects are **pointer lines only** (`[INFO id="N"]`, `[TASK_LIST id="N"]`, `[IMAGE id="N"]`, `[GRAPH id="N"]`, `[TABLE id="N"]`). Content lives in object tables / `objects.payload`.
- Move object = cut/paste the pointer line ([`document_marker_text.py`](services/document_marker_text.py)).

### Lists and tables

Lists stay fenced in the file string (`[BULLET_LIST]…`, `[ORDERED_LIST]…`). **Tables are objects** (`type=table`, `payload.rows`). Pointer `[TABLE id]` for plain grids; `[GRAPH id]` when `payload.chart.enabled` (same object type). Legacy structure fences `[TABLE]…[/TABLE]` without an id migrate to a table object on open.

### How objects fit in

| Rule | Meaning |
|------|---------|
| Pointer only in SoT | Never store info body / tasks inside the file text |
| Top-level only | Pointers are top-level parts — never inside a list/table fence |
| Delete cascades | Removing a pointer goes through objects cascade |

Creating via `POST /files/:id/objects` inserts a typed pointer at `block_index`.

## Two projections of the same file

| Representation | Where | Used for |
|----------------|-------|----------|
| **Editor text** | `files.document_json` (v4 header) | Persistence, editor, cut/paste/move |
| **Agent text** | Derived on demand | AI reading/writing, search, diffs |

Agent text **expands** pointers with live object payloads (same fences as before). Apply **collapses** back to pointers + `object_updates` ([`document_agent_text.py`](services/document_agent_text.py)). Rejects unknown ids and silent drops of existing embeds.

| Fence (agent) | Shape |
|-------|--------|
| `SPACER` | Extra blank gaps |
| `TASK_LIST` | ACTIVE/DONE checkbox lines (expanded) |
| `INFO` | First line title, remaining body (expanded) |
| `IMAGE` | `caption` + optional `url` (expanded) |
| `GRAPH` | Chart table sugar: chartType + 2 TSV rows (+ colors); object type is `table` |
| `TABLE` | Full grid TSV rows (expanded); object type `table` |

Format examples: [`content/production_agent/reference.md`](../../../content/production_agent/reference.md)

## Modules

| Module | Role |
|--------|------|
| [`services/document_marker_text.py`](services/document_marker_text.py) | Editor text (v4): migrate, pointers, insert/move/remove; shared emit helpers |
| [`services/document_v3.py`](services/document_v3.py) | Legacy v3 JSON parse/migrate; insert pointer delegates to marker text |
| [`services/document_agent_text.py`](services/document_agent_text.py) | Editor text ↔ expanded agent text |
| [`services/document_promote.py`](services/document_promote.py) | Promote legacy inline embeds → object rows; writes v4 editor text |
| [`services/file_versions.py`](services/file_versions.py) | Snapshot before agent/automation writes |
| [`routes/files.py`](routes/files.py) | File CRUD |
| [`routes/file_versions.py`](routes/file_versions.py) | History and `POST /files/:id/diff` |
| [`routes/topics.py`](routes/topics.py) | Topics — the container files live in |

## Sending documents to the app

`File.to_dict()` includes `document_json` unless a caller opts out, and the file lists the app reads from **must not** opt out. The topic screen renders every file of a topic inline from one `GET /topics/:id/files` response; there is no second request per file.

Leaving the document out of that response is a data-loss bug, not a display one: each editor opens empty, and the first keystroke saves that emptiness over the stored document. `tests/files/test_file_routes_document.py` guards it.

`include_document=False` is for callers that only want names — currently the agent's file listing, so a tool call does not pour every document into the prompt.

## Rules

- Persist editor text (v4 header). Migrate legacy v3 JSON on read; do not write new v3 JSON.
- Never store expanded object bodies in the file — pointers only.
- Never drop an embed pointer during a programmatic edit; fail loudly instead.
- Save a file version before any agent or automation write.
- Any endpoint the editor loads a file from must include `document_json`.

## Known gaps

Agent text round-trip is not yet lossless. Open issues, worst first:

| Gap | Effect |
|-----|--------|
| `run_agent` commits without checking tool errors after `applied` | A failed later tool can still leave earlier writes committed |
| `_escape_cell` escapes `\` and in-cell tab; rows join with visible `\t` | A newline in a table cell becomes an extra row on read |
| Unmatched fence markers in plain text advance one char without emitting it | Text like `Hello [TABLE] world` loses characters |
| `_sync_task_list` archives every task and inserts new rows | Task ids churn on each apply; `view_task_memberships` point at archived tasks |
| Malformed list/task lines are skipped with `continue` | Items vanish with no error |
| Spans not in v4 editor text yet | Migrate/agent paths drop inline formatting until span encoding ships |

Agent write path: `commit_agent_file_apply` promotes legacy embeds, versions the file, writes v4 `document_json`, applies `object_updates`, then purges unreferenced embeds. Review proposals include `object_updates`; Accept uses `POST /files/:id/apply-agent-text` (not a bare document PATCH). Id-less `[TABLE]` fences are rejected on write.
