# App files — in-app document editor

Files are **structured documents**, not plain text. The Flutter editor reads and writes the v3 block tree in `files.document_json`.

## Principles

| Principle | Rule |
|-----------|------|
| Structured model | Paragraphs, headings, lists, tables, and embeds are **document nodes** in the block array |
| Not DB objects | Lists and tables are inline nodes in JSON — not separate database rows |
| Source of truth | `document_json` only; no synchronized plain-text copy in the app |
| Persistence | Edits → `DocumentCodec.serialize` → API `PATCH document_json` |
| Agent text | Never edited in-app; see [PRODUCTION_AGENT.md](../../system_app_back_end/docs/PRODUCTION_AGENT.md) |

## Node types

| Node | JSON `type` | Editor widget |
|------|-------------|---------------|
| Paragraph | `paragraph` | `FormattedTextField` (multiline, `\n` = line break) |
| Heading | `heading` | `FormattedTextField` (title style) |
| Bullet list | `bullet_list` | `RichListEditor` |
| Ordered list | `ordered_list` | `RichListEditor` |
| Table | `table` | `RichTableEditor` |
| Embed | `embed` | Placeholder / future object UI |

Position is **array order** in `blocks[]`.

## Target UX (Word-like)

The user should eventually experience **one continuous document**:

- One logical cursor across node boundaries
- Selection spanning paragraphs, lists, tables, and embeds
- Copy/cut/paste and formatting on mixed selections
- Undo/redo for the whole document

## Current implementation

Today the editor uses **block widgets** ([`block_document_editor.dart`](../lib/features/document/block_document_editor.dart)):

- Each node type renders its own focusable surface
- Paragraphs coalesce on load; Enter inserts `\n` within a paragraph
- Per-block undo; no cross-block selection yet

## Keyboard semantics

| Context | Key | Behavior |
|---------|-----|----------|
| Paragraph | Enter | New line in same paragraph |
| Paragraph | Backspace at start (empty block) | Merge with previous paragraph |
| List | Enter (non-empty item) | New list item |
| List | Enter (empty item) | Exit list → paragraph |
| List | Backspace (empty item) | Remove item or exit list |
| Table | Enter | Move to cell below; add row on last row |
| Table | Shift+Enter | Line break inside cell |
| Table | Tab | Next cell |
| Table | Right-click | Add column (after current column) |

## Rich text

Inline bold, italic, underline, size, and color use span marks on `text` fields.

**Do not break** the rules in [`rich_text/RICH_TEXT.md`](../lib/features/document/rich_text/RICH_TEXT.md).

## Future: ContinuousDocumentSession

Planned modules (not yet implemented):

| Module | Role |
|--------|------|
| `DocumentSession` | Owns block tree + active selection |
| `DocumentSelection` | Anchor/focus across block boundaries |
| `DocumentClipboard` | Mixed copy/cut/paste |
| `DocumentEditHistory` | Whole-document undo/redo |
| `DocumentKeyRouter` | Enter/Backspace/Tab routing |

Block widgets become **views** over session slices rather than independent save units.

## Code map

| Path | Role |
|------|------|
| [`document_model.dart`](../lib/features/document/document_model.dart) | Dart node types |
| [`document_codec.dart`](../lib/features/document/document_codec.dart) | JSON parse/serialize |
| [`block_document_editor.dart`](../lib/features/document/block_document_editor.dart) | Main editor |
| [`rich_text/`](../lib/features/document/rich_text/) | Span formatting stack |
