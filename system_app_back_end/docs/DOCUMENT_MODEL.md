# Document model (v2)

## Decision: inline marker text (Option A)

After comparing **inline markers** vs **structured JSON runs**, we chose **plain `files.body` text with embed markers**.

### Marker syntax

| Embed | Marker | Typical placement |
|-------|--------|-------------------|
| Task | `{{task:<id>}}` | Own line between text paragraphs |
| Information | `{{info:<id>}}` | Own line |

Example body:

```text
# Weekly goals

Focus on shipping the rewrite.

{{task:42}}
{{task:43}}

Notes for later…
```

Rules:

- Markers are **exact** strings; IDs are integer primary keys from `objects` → `tasks` / `information_pieces`.
- One marker per line (simplifies reorder and Flutter layout).
- Plain text may use Markdown informally; rendering is plain unless a view opts into rich text later.
- Agent edits treat the body as one string; tools resolve markers via `objects` + entity tables.

### Spike scores (1–5, higher is better)

| Criterion | Markers (A) | JSON runs (B) |
|-----------|-------------|---------------|
| Agent edit simplicity | 5 | 3 |
| Deterministic diff quality | 5 | 4 |
| Flutter render complexity | 4 | 3 |
| Embed drag/reorder | 4 | 5 |

**Why markers win:** The production agent and review diff operate on full-document snapshots. Unified line diff on a single string is trivial and readable. LLMs edit prose naturally; JSON run arrays add escape/sync burden. Reorder is solved by moving marker lines and updating `objects.sort_key`.

### Object anchoring

`objects.anchor` JSON stores redundant hints for fast lookup:

```json
{"kind": "marker", "marker": "{{task:42}}", "line": 4}
```

`line` is recomputed on parse; used for DnD without scanning on every keystroke.

### Versioning

Every applied write (user, agent, automation) saves `file_versions.body` before updating `files.body`.

### RTL / bilingual

Text direction follows document locale in the editor widget; markers are LTR tokens and stay visually distinct in Hebrew documents (see `BILINGUAL.md`).
