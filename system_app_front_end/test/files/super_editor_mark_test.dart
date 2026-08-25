import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:system_app_front_end/areas/files/editor/super_editor_mark.dart';
import 'package:system_app_front_end/areas/files/model/object_embed_node.dart';

void main() {
  DocumentSelection collapsed(String nodeId, int offset) =>
      DocumentSelection.collapsed(
        position: DocumentPosition(
          nodeId: nodeId,
          nodePosition: TextNodePosition(offset: offset),
        ),
      );

  DocumentSelection range(String nodeId, int start, int end) => DocumentSelection(
        base: DocumentPosition(
          nodeId: nodeId,
          nodePosition: TextNodePosition(offset: start),
        ),
        extent: DocumentPosition(
          nodeId: nodeId,
          nodePosition: TextNodePosition(offset: end),
        ),
      );

  test('collapsed caret expands to the line it sits on', () {
    final doc = MutableDocument(
      nodes: [
        ParagraphNode(id: 'p', text: AttributedText('first line\nsecond line')),
      ],
    );
    final next = caretLineSelection(doc, collapsed('p', 14));
    expect(next, isNotNull);
    expect(next!.isCollapsed, isFalse);
    expect((next.base.nodePosition as TextNodePosition).offset, 11);
    expect((next.extent.nodePosition as TextNodePosition).offset, 22);
  });

  test('an expanded mark is left alone', () {
    final doc = MutableDocument(
      nodes: [
        ParagraphNode(id: 'p', text: AttributedText('alpha beta')),
      ],
    );
    final marked = range('p', 0, 5);
    expect(caretLineSelection(doc, marked), marked);
  });

  test('a caret on an object block is not expanded to a text line', () {
    final doc = MutableDocument(
      nodes: [
        ObjectEmbedNode(id: 'embed:1', objectId: 1, objectType: 'info'),
      ],
    );
    final sel = DocumentSelection.collapsed(
      position: const DocumentPosition(
        nodeId: 'embed:1',
        nodePosition: UpstreamDownstreamNodePosition.downstream(),
      ),
    );
    expect(caretLineSelection(doc, sel), sel);
  });
}
