import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:system_app_front_end/areas/files/editor/remote_selection.dart';

MutableDocument doc(List<String> lines) => MutableDocument(
  nodes: [
    for (final line in lines)
      ParagraphNode(id: Editor.createNodeId(), text: AttributedText(line)),
  ],
);
void main() {
  test('remote insertion preserves selection in an unchanged paragraph', () {
    final before = doc(['first', 'writing here']);
    final after = doc(['new remote paragraph', 'first', 'writing here']);
    final selection = DocumentSelection.collapsed(
      position: DocumentPosition(
        nodeId: before.getNodeAt(1)!.id,
        nodePosition: const TextNodePosition(offset: 4),
      ),
    );
    final next = remapRemoteSelection(before, after, selection)!;
    expect(next.extent.nodeId, after.getNodeAt(2)!.id);
    expect((next.extent.nodePosition as TextNodePosition).offset, 4);
  });
  test(
    'shortened/deleted paragraph clamps caret instead of jumping to file end',
    () {
      final before = doc(['long old paragraph', 'last']);
      final after = doc(['hi', 'last']);
      final selection = DocumentSelection.collapsed(
        position: DocumentPosition(
          nodeId: before.getNodeAt(0)!.id,
          nodePosition: const TextNodePosition(offset: 12),
        ),
      );
      final next = remapRemoteSelection(before, after, selection)!;
      expect(next.extent.nodeId, after.getNodeAt(0)!.id);
      expect((next.extent.nodePosition as TextNodePosition).offset, 2);
      expect(remapRemoteSelection(before, after, null), isNull);
    },
  );
}
