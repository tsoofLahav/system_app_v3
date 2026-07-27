# Document editor (Flutter)

Rich file editor under `lib/features/document/`.

**Canonical UX and architecture:** [`../../docs/APP_FILES.md`](../../docs/APP_FILES.md)

## Structure

| Path | Role |
|------|------|
| [`document_model.dart`](document_model.dart) | Node types (paragraph, heading, list, table, embed) |
| [`document_codec.dart`](document_codec.dart) | JSON parse/serialize |
| [`block_document_editor.dart`](block_document_editor.dart) | Main block-based editor |
| [`document_editor.dart`](document_editor.dart) | Shell around block editor |
| [`rich_text/`](rich_text/) | Span formatting stack |
| [`rich_text/list_editor.dart`](rich_text/list_editor.dart) | Bullet/ordered list node |
| [`rich_text/rich_table_editor.dart`](rich_text/rich_table_editor.dart) | Table node |

## Rich text rules

See [`rich_text/RICH_TEXT.md`](rich_text/RICH_TEXT.md).

## Backend

JSON schema: [`../../../system_app_back_end/docs/DOCUMENT_MODEL.md`](../../../system_app_back_end/docs/DOCUMENT_MODEL.md)

Agent text format: [`../../../system_app_back_end/docs/PRODUCTION_AGENT.md`](../../../system_app_back_end/docs/PRODUCTION_AGENT.md)
