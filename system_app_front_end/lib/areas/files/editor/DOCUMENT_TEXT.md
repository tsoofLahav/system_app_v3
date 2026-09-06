# Document text (source of truth)

A file’s body is **marker text**, not a v3 JSON block tree. Disk / API SoT is the string in `files.document_json` (`%%system_app_document v4` + body).

**Runtime editing surface** is Super Editor (`MutableDocument`). Load/save goes through [`marker_super_editor_bridge.dart`](../model/marker_super_editor_bridge.dart). [`DocumentBuffer`](../model/document_buffer.dart) remains available for marker-range helpers and tests; it is not the file-editor SoT anymore.

Spans / inline formatting round-trip in paragraph, heading, and list lines via Super Editor markdown (`**bold**`, `*italic*`, `¬underline¬`, `~strike~`, plus CommonMark links). **Font size and colour** still drop on save (no compact encoding yet). Object pointer lines are never parsed as styled text. Migration from v3 drops other spans.

Backend twin: [`system_app_back_end/areas/files/AREA.md`](../../../../system_app_back_end/areas/files/AREA.md). Fluent rules for embeds: [`FLUENT_TEXT.md`](FLUENT_TEXT.md).

## Persistence header

```text
%%system_app_document v4
<body…>
```

Bodies without this header that parse as v3 JSON are migrated on read and rewritten on save.

## Editor text vs agent text

| Layer | Object markers | Who uses it |
|-------|----------------|-------------|
| **Editor text (SoT)** | Pointer only: `[INFO id="42"]` | DB, Super Editor bridge, move/cut/paste |
| **Agent text** | Expanded fences with object payloads | Production agent tools |

Structure markers for lists are shared. Tables are **objects** (pointer in the file).

## Structure grammar

- Blocks separated by `\n\n`. Soft line break inside a paragraph = `\n`.
- Extra blank gaps: `[SPACER]` or `[SPACER n="N"]` (N 1–12). Load expands `n` to that many empty paragraphs (agent apply may still emit a single `n="N"` for a blank run inside paragraph text).
- Headings: `#` … `######` lines.
- Lists: `[BULLET_LIST]…[/BULLET_LIST]`, `[ORDERED_LIST]…[/ORDERED_LIST]` (mapped to Super Editor `ListItemNode`s).
- Legacy structure tables: `[TABLE]…[/TABLE]` — migrated on open to a `table` object + pointer.

### Object pointers (SoT)

One line each — **no** payload inside the file:

```text
[INFO id="42"]
[TASK_LIST id="7"]
[IMAGE id="5"]
[GRAPH id="8"]
[TABLE id="11"]
```

`[GRAPH id]` and `[TABLE id]` both point at `objects.type = table`. Use `[GRAPH]` when `payload.chart.enabled` (chart quality); otherwise `[TABLE]`.

Legacy fallback: `[EMBED id="N"]` (type resolved from the objects table).

Object **content** lives in object tables / `objects.payload`. Deleting a pointer cascades to the object row.

### Links and inline styles

Bold / italic / underline / strikethrough and `http(s)://` / `www.` URLs round-trip in paragraph / heading / list-item text (`**` / `*` / `¬` / `~` / `[label](url)`). Load restores Super Editor attributions. Do not put markdown on pointer lines. Font size and colour are not encoded yet.

### Move

Cut the pointer line and paste it elsewhere (or reorder the Super Editor embed node, then save). The move itself must not leave an empty paragraph behind — the save no longer prunes one, because a blank line beside an object may be the user's ([`FLUENT_TEXT.md`](FLUENT_TEXT.md)).

## Agent projection

- **Read:** expand each pointer using `objects_by_id` into expanded fences (`[INFO id="42"]` … `[/INFO]`, `[TABLE id="11"]` … `[/TABLE]`, etc.).
- **Write:** collapse expanded fences back to pointers + `object_updates`; reject unknown ids and silent drops of existing embeds.
