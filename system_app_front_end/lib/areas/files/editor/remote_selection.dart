import 'package:super_editor/super_editor.dart';

/// Restore a reading/writing position across a remote document replacement.
/// Unchanged paragraphs match by text nearest the old index; edited/deleted
/// paragraphs fall back to the same index, clamped to a valid position.
DocumentSelection? remapRemoteSelection(
  Document oldDocument,
  Document newDocument,
  DocumentSelection? selection,
) {
  if (selection == null || newDocument.nodeCount == 0) return null;
  DocumentPosition map(DocumentPosition position) {
    final oldNode = oldDocument.getNodeById(position.nodeId);
    final oldIndex = oldDocument.getNodeIndexById(position.nodeId);
    DocumentNode? node = newDocument.getNodeById(position.nodeId);
    if (node == null && oldNode is TextNode) {
      var distance = 1 << 30;
      for (var i = 0; i < newDocument.nodeCount; i++) {
        final candidate = newDocument.getNodeAt(i);
        if (candidate is TextNode &&
            candidate.text.toPlainText() == oldNode.text.toPlainText() &&
            (i - oldIndex).abs() < distance) {
          node = candidate;
          distance = (i - oldIndex).abs();
        }
      }
    }
    node ??= newDocument.getNodeAt(
      oldIndex.clamp(0, newDocument.nodeCount - 1),
    )!;
    final oldPosition = position.nodePosition;
    return DocumentPosition(
      nodeId: node.id,
      nodePosition: node is TextNode && oldPosition is TextNodePosition
          ? TextNodePosition(
              offset: oldPosition.offset.clamp(0, node.text.length),
            )
          : node.beginningPosition,
    );
  }

  return DocumentSelection(
    base: map(selection.base),
    extent: map(selection.extent),
  );
}
