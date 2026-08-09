# Document text (source of truth)

A file’s body is **marker text**, not a v3 JSON block tree. The editor’s in-memory SoT is [`DocumentBuffer`](../model/document_buffer.dart) (`text` + range-indexed `parts`). DB column `files.document_json`, typing (`replaceRange` / `replacePartSlice`), and cut/paste/move all operate on that string. `RichDocument` / codec parse is a **view** for widgets and legacy structural helpers — not the session SoT.

Spans / inline formatting are **not** encoded yet (next step). Migration from v3 drops spans.

Backend twin: [`system_app_back_end/areas/files/AREA.md`](../../../../system_app_back_end/areas/files/AREA.md). Fluent caret rules: [`FLUENT_TEXT.md`](FLUENT_TEXT.md).

## Persistence header

```text
%%system_app_document v4
<body…>
```

Bodies without this header that parse as v3 JSON are migrated on read and rewritten on save.

## Editor text vs agent text

| Layer | Object markers | Who uses it |
|-------|----------------|-------------|
| **Editor text (SoT)** | Pointer only: `[INFO id="42"]` | DB, editor, move/cut/paste |
| **Agent text** | Expanded fences with object payloads | Production agent tools |

Structure markers are shared.

## Structure grammar

- Blocks separated by `\n\n`. Soft line break inside a paragraph = `\n`.
- Extra blank gaps: `[SPACER]` or `[SPACER n="N"]` (N 1–12).
- Headings: `#` … `######` lines.
- Lists: `[BULLET_LIST]…[/BULLET_LIST]`, `[ORDERED_LIST]…[/ORDERED_LIST]`.
- Tables: `[TABLE]…[/TABLE]` (tab-separated cells).

### Object pointers (SoT)

One line each — **no** title/body/tasks inside the file:

```text
[INFO id="42"]
[TASK_LIST id="7"]
[IMAGE id="5"]
[GRAPH id="8"]
```

Legacy fallback: `[EMBED id="N"]` (type resolved from the objects table).

Object **content** lives in object tables. Deleting a pointer cascades to the object row (same as today).

### Move

Cut the pointer line and paste it elsewhere in the string. Never split a paragraph into two stored units around an embed.

## Agent projection

- **Read:** expand each pointer using `objects_by_id` into today’s expanded fences (`[INFO id="42"]` … `[/INFO]`, etc.).
- **Write:** collapse expanded fences back to pointers + `object_updates`; reject unknown ids and silent drops of existing embeds.
