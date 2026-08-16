# Production agent reference

Call the `reference` tool with `section` when you need examples. Do not memorize this whole file up front.

## agent_text

You read/write **agent text** (never raw JSON, never the stored pointer-only form). The app stores pointer markers for embeds; `open_file` **expands** them so you see real task/info/graph content. When you write, keep every embed `id="…"` — the app collapses bodies back into object rows.

Real newlines separate lines (`open_file` also returns `document_lines` with 1-based numbers). Extra blank gaps use `[SPACER n="…"]` (n 1–12; omit n for 1). Table/graph cells are joined with the two characters `\t` (not a raw tab).

### Spacer

```text
Intro paragraph.

[SPACER n="2"]

Next section.
```

### Heading

```text
## Goals
```

### Lists

```text
[BULLET_LIST]
- Item one
  - Nested item
- Item two
[/BULLET_LIST]

[ORDERED_LIST]
1. Step one
2. Step two
[/ORDERED_LIST]
```

### Table object

```text
[TABLE id="11"]
Header A\tHeader B
Value 1\tValue 2
[/TABLE]
```

Cells are separated by the two characters `\t`. In-cell tab/backslash are escaped as `\\t` and `\\`. Preserve `id="…"`. Never invent object ids. A `[TABLE]` fence **without** `id="…"` is rejected on write.

### Task list embed

```text
[TASK_LIST id="42"]
ACTIVE:
- [ ] Call clinic
DONE:
- [x] Done item
[/TASK_LIST]
```

### Info embed

```text
[INFO id="17"]
Lens notes
Practice morning and evening.
Track progress weekly.
[/INFO]
```

First line = title; rest = body. `open_file` may also return `object_extras` with `title` and `Links: [{ id, type, title }]`.

### Image embed

```text
[IMAGE id="5" caption="Screenshot" url="/uploads/shot.png"]
```

### Chart table (graph sugar)

A graph is a **table object with chart quality** — same object type, pointer tagged `[GRAPH]`:

```text
[GRAPH id="8" chartType="bar"]
Week1\tWeek2\tWeek3
10\t20\t15
#4A90D9\t#E07A5F\t#3D405B
[/GRAPH]
```

Row 1 = labels, row 2 = values, optional row 3 = colors. Same `\t` cell separator. Preserve every `id="…"`. Never invent object ids.

## tools

### `list`

```json
{ "kind": "files", "topic_id": 3 }
```

`kind`: `topics` | `files` | `objects`. `topic_id` `0` = whole workspace.

### `find_file`

```json
{ "file_id": 0, "name": "plan", "topic_id": 3 }
```

Or `{ "file_id": 12, "name": "", "topic_id": 0 }`.

### `find_object`

```json
{ "object_id": 0, "name": "clinic", "type": "task_list", "topic_id": 0 }
```

### `open_file`

Load one file. Returns `document_plain` (agent text), `document_lines` (`[{line, text}, …]` 1-based), and optional `object_extras`.

### `create_object`

```json
{ "file_id": 12, "type": "task_list", "title": "Week", "body": "", "after_line": 0 }
```

Creates the embed + pointer; returns `object_id`. Then `open_file` + `patch_file` to fill rows/tasks. `after_line` `0` = end of file.

### `reference`

This help. `section`: `agent_text` | `tools` | `all`.

### `patch_file` — add / remove / replace by line

```json
{
  "file_id": 12,
  "edits": [
    { "op": "replace", "line": 4, "end_line": 4, "text": "Lunch: soup" },
    { "op": "add", "line": 3, "end_line": 0, "text": "Milk\\t1" },
    { "op": "remove", "line": 9, "end_line": 0, "text": "" }
  ]
}
```

`replace` changes an existing line or range (rephrase, sharpen, enrich). `add` inserts **new** data or a new point **after** `line` (`0` = start). `remove` deletes an unneeded, unwanted, or repeating line. Inside a fence, edit **content** lines and keep markers intact. New text must match that block’s pattern (e.g. table cells with `\t`). When neighbors use `[SPACER …]`, keep spacing consistent with the file. Put **all** edits for the ask in **one** `patch_file`, with every `line` from the same `open_file`.


### `rewrite_file` — whole file only when asked

```json
{
  "file_id": 12,
  "document_text": "## Plan\n\nNew body…\n"
}
```
