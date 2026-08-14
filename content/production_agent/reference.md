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

### `search`

Find files by name or agent-text substring inside scope.

### `open_file`

Load one file. Returns `document_plain` (agent text), `document_lines` (`[{line, text}, …]` 1-based), and optional `object_extras`.

### `reference`

This help. `section`: `agent_text` | `tools` | `all`.

### `patch_file` — all partial edits by line range

```json
{
  "file_id": 12,
  "edits": [
    {
      "start_line": 4,
      "end_line": 4,
      "new_text": "Lunch: soup"
    }
  ]
}
```

Add a table row by replacing one data line with that line plus the new row (`document_lines` numbers):

```json
{
  "file_id": 12,
  "edits": [
    {
      "start_line": 3,
      "end_line": 3,
      "new_text": "Eggs\\t6\nMilk\\t1"
    }
  ]
}
```

Same pattern for `[INFO id="…"]` / `[TASK_LIST id="…"]`. Outside the edited lines, including `[SPACER]`, stays unchanged.

### `rewrite_file` — whole file only when asked

```json
{
  "file_id": 12,
  "document_text": "## Plan\n\nNew body…\n"
}
```

### `search_tasks`

Search task titles in scoped files.
