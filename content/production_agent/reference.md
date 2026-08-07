# Production agent reference

Call the `reference` tool with `section` when you need examples. Do not memorize this whole file up front.

## agent_text

You read/write **agent text** (never raw JSON). Double newline separates blocks. Single newline inside a paragraph is a line break. Extra blank lines use `[SPACER n="…"]` (n 1–12; omit n for 1).

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

### Table

```text
[TABLE]
Header A	Header B
Value 1	Value 2
[/TABLE]
```

Tab between cells. Escape literal tab/backslash as `\t` and `\\`.

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

### Graph embed

```text
[GRAPH id="8" chartType="bar"]
Week1	Week2	Week3
10	20	15
#4A90D9	#E07A5F	#3D405B
[/GRAPH]
```

Row 1 = labels, row 2 = values, optional row 3 = colors. Preserve every `id="…"`. Never invent object ids.

## tools

### `search`

Find files by name or agent-text substring inside scope.

### `open_file`

Load one file. Returns `document_plain` (agent text) and optional `object_extras`.

### `reference`

This help. `section`: `agent_text` | `tools` | `all`.

### `patch_file` — update existing content

```json
{
  "file_id": 12,
  "replacements": [
    {
      "old_text": "Lunch: salad",
      "new_text": "Lunch: soup"
    }
  ]
}
```

`old_text` must match `document_plain` uniquely (copy from `open_file`). Outside the match, including `[SPACER]`, stays unchanged.

### `move_text` — place new content

```json
{
  "file_id": 12,
  "content": "- [ ] Buy oats",
  "anchor_type": "after_text",
  "line": 0,
  "text": "ACTIVE:"
}
```

`anchor_type`: `end` | `start` | `after_line` | `before_line` | `after_text`. For line anchors set `line` (1-based); for `after_text` set `text`; otherwise pass `line=0` and `text=""`.

### `rewrite_file` — whole file only when asked

```json
{
  "file_id": 12,
  "document_text": "## Plan\n\nNew body…\n"
}
```

### `search_tasks`

Search task titles in scoped files.
