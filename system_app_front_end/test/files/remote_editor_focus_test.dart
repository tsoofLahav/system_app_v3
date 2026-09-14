import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:system_app_front_end/core/app_state.dart';
import 'package:system_app_front_end/areas/files/data/app_file.dart';
import 'package:system_app_front_end/areas/files/editor/document_sync.dart';
import 'package:system_app_front_end/areas/files/editor/document_editor_controller.dart';
import 'package:system_app_front_end/areas/files/editor/super_document_editor.dart';
import 'package:system_app_front_end/areas/objects/data/object_embed.dart';

const body = '%%system_app_document v4\n\nFirst paragraph\n\nLast paragraph';
const file = AppFile(id: 77, topicId: 1, name: 'Test', documentJson: body);

class MemoryState extends AppState {
  MemoryState() {
    filesById[file.id] = file;
  }
  DocumentVersion version = const DocumentVersion(body, 1);
  @override
  Future<DocumentVersion> readDocumentVersion(int id) async => version;
  @override
  Future<List<ObjectEmbed>> loadEmbedsForFile(
    int id, {
    bool notify = true,
  }) async => [];
}

void main() {
  testWidgets(
    'entry focuses end; passive remount retains caret without requesting focus',
    (tester) async {
      final state = MemoryState()..pendingFocusFileId = file.id;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SuperDocumentEditor(file: file, state: state),
          ),
        ),
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      var surface = tester.widget<SuperEditor>(find.byType(SuperEditor));
      expect(surface.focusNode!.hasPrimaryFocus, isTrue);
      expect(state.pendingFocusFileId, isNull);
      final doc = surface.editor.document;
      surface.editor.execute([
        ChangeSelectionRequest(
          DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: doc.getNodeAt(0)!.id,
              nodePosition: const TextNodePosition(offset: 3),
            ),
          ),
          SelectionChangeType.placeCaret,
          SelectionReason.userInteraction,
        ),
      ]);
      surface.focusNode!.unfocus();
      await tester.pump();
      state.version = const DocumentVersion('$body\n\nRemote addition', 2);
      final sync = DocumentEditorRegistry.synchronizeAll();
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await sync;
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      surface = tester.widget<SuperEditor>(find.byType(SuperEditor));
      expect(surface.focusNode!.hasPrimaryFocus, isFalse);
      final selection = surface.editor.composer.selection!;
      expect((selection.extent.nodePosition as TextNodePosition).offset, 3);
      expect(selection.extent.nodeId, surface.editor.document.getNodeAt(0)!.id);
      expect(state.pendingFocusFileId, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      state.dispose();
    },
  );
  testWidgets('iOS entry opens keyboard but remount with retained focus does not', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final state = MemoryState()..pendingFocusFileId = file.id;
    try {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SuperDocumentEditor(file:file,state:state))));
      for(var i=0;i<8;i++) { await tester.pump(const Duration(milliseconds:100)); }
      var surface = tester.widget<SuperEditor>(find.byType(SuperEditor));
      expect(surface.focusNode!.hasPrimaryFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      tester.testTextInput.hide();
      // The focus node remains primary when iOS dismisses the keyboard.
      expect(surface.focusNode!.hasPrimaryFocus, isTrue);
      state.version = const DocumentVersion('$body\n\nRemote addition',2);
      final sync = DocumentEditorRegistry.synchronizeAll();
      for(var i=0;i<8;i++) { await tester.pump(const Duration(milliseconds:100)); }
      await sync;
      surface = tester.widget<SuperEditor>(find.byType(SuperEditor));
      expect(tester.testTextInput.isVisible, isFalse);
      expect(surface.editor.composer.selection, isNotNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      state.dispose();
      debugDefaultTargetPlatformOverride = null;
    }
  });

}
