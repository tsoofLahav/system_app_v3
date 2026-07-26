# Document editor (Flutter)

Rich file editor under `lib/features/document/`.

## Structure

| Path | Role |
|------|------|
| [`document_model.dart`](document_model.dart) | Sealed node types |
| [`document_codec.dart`](document_codec.dart) | JSON parse/serialize + plain-text export |
| [`document_editor.dart`](document_editor.dart) | Node list, insert menu, reorder, save |
| [`nodes/paragraph_node_widget.dart`](nodes/paragraph_node_widget.dart) | Rich paragraph |
| [`nodes/flow_node_widgets.dart`](nodes/flow_node_widgets.dart) | Table, list, image, graph |
| [`objects/document_object_widgets.dart`](objects/document_object_widgets.dart) | Task list + info object UI |
| [`rich_text/`](rich_text/) | v1 span formatting stack (ported from `legacy/v1`) |

## Port map from v1 (`legacy/v1`)

| v1 | v2 |
|----|-----|
| `text` block + spans | `paragraph` node |
| `table` block | `table` node |
| `points_list` block | `list` node |
| `image` block | `image` node |
| `graph` block | `graph` node |
| `task_list` block + row blocks | `task_list` object (tasks live in object widget only) |
| `details` block | `info` object |

## Rich text rules

See [`rich_text/RICH_TEXT.md`](rich_text/RICH_TEXT.md).
