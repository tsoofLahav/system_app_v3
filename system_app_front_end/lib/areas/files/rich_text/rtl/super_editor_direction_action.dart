import 'package:super_editor/super_editor.dart';

/// One undoable operation targets complete touched paragraphs/list items.
/// A selection ending at the next paragraph's start does not touch that text.
List<EditRequest> paragraphDirectionRequests(
  Document document,
  DocumentSelection selection,
  String direction,
) {
  if (!['rtl', 'ltr', 'auto'].contains(direction)) return [];
  final nodes = document.getNodesInside(selection.base, selection.extent);
  final end = selection.normalize(document).end;
  final requests = <EditRequest>[];
  for (final node in nodes) {
    if (node is! TextNode) continue;
    if (!selection.isCollapsed &&
        nodes.length > 1 &&
        node.id == end.nodeId &&
        end.nodePosition is TextNodePosition &&
        (end.nodePosition as TextNodePosition).offset == 0)
      continue;
    final metadata = node.copyMetadata();
    if (direction == 'auto') {
      metadata.remove('writingDirection');
    } else {
      metadata['writingDirection'] = direction;
    }
    requests.add(
      ReplaceNodeRequest(
        existingNodeId: node.id,
        newNode: node.copyAndReplaceMetadata(metadata),
      ),
    );
  }
  return requests;
}
