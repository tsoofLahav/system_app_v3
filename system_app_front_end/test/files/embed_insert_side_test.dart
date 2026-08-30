import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:system_app_front_end/areas/files/editor/embed_caret_bridge.dart';

void main() {
  DocumentSelection onEmbed(UpstreamDownstreamNodePosition position) {
    return DocumentSelection.collapsed(
      position: DocumentPosition(
        nodeId: 'embed:1',
        nodePosition: position,
      ),
    );
  }

  test('caret on the leading edge of an object inserts above it', () {
    expect(
      embedInsertGoesBefore(
        onEmbed(const UpstreamDownstreamNodePosition.upstream()),
      ),
      isTrue,
    );
  });

  test('caret on the trailing edge of an object inserts below it', () {
    expect(
      embedInsertGoesBefore(
        onEmbed(const UpstreamDownstreamNodePosition.downstream()),
      ),
      isFalse,
    );
  });

  test('a mark across the object does not count as before', () {
    expect(
      embedInsertGoesBefore(
        DocumentSelection(
          base: DocumentPosition(
            nodeId: 'embed:1',
            nodePosition: const UpstreamDownstreamNodePosition.upstream(),
          ),
          extent: DocumentPosition(
            nodeId: 'embed:1',
            nodePosition: const UpstreamDownstreamNodePosition.downstream(),
          ),
        ),
      ),
      isFalse,
    );
  });
}
