import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:system_app_front_end/areas/files/editor/object_embed_component.dart';

void main() {
  test('ObjectEmbedComponentViewModel equality includes selection', () {
    final plain = ObjectEmbedComponentViewModel(
      nodeId: 'embed:1',
      objectId: 1,
      objectType: 'info',
      selectionColor: Colors.transparent,
    );
    expect(
      plain,
      equals(
        ObjectEmbedComponentViewModel(
          nodeId: 'embed:1',
          objectId: 1,
          objectType: 'info',
          selectionColor: Colors.transparent,
        ),
      ),
    );

    final selected = ObjectEmbedComponentViewModel(
      nodeId: 'embed:1',
      objectId: 1,
      objectType: 'info',
      selection: DocumentNodeSelection(
        nodeId: 'embed:1',
        nodeSelection: const UpstreamDownstreamNodeSelection.all(),
      ),
      selectionColor: const Color(0xFF37899E),
    );
    expect(plain == selected, isFalse);

    final tinted = ObjectEmbedComponentViewModel(
      nodeId: 'embed:1',
      objectId: 1,
      objectType: 'info',
      selectionColor: const Color(0xFF37899E),
    );
    expect(plain == tinted, isFalse);
  });
}
