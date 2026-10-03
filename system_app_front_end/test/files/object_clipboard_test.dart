import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:system_app_front_end/core/app_state.dart';
import 'package:system_app_front_end/areas/files/data/app_file.dart';
import 'package:system_app_front_end/areas/files/editor/document_sync.dart';
import 'package:system_app_front_end/areas/files/editor/super_document_editor.dart';
import 'package:system_app_front_end/areas/files/model/object_embed_node.dart';
import 'package:system_app_front_end/areas/files/editor/document_editor_controller.dart';
import 'package:system_app_front_end/areas/objects/data/object_embed.dart';

const body = '%%system_app_document v4\n\n[INFO id="1"]\n\nDestination';
const file = AppFile(id: 77, topicId: 1, name: 'Test', documentJson: body);
const info = ObjectEmbed(
  id: 1,
  fileId: 77,
  type: 'info',
  information: {'title': 'Title', 'body': '☐ Task\n• Item'},
);

class MemoryState extends AppState {
  MemoryState() {
    filesById[77] = file;
    embedsByFileId[77] = [info];
  }
  final sources = <int>[];
  bool fail = false;
  @override
  Future<DocumentVersion> readDocumentVersion(int id) async => DocumentVersion(
    filesById[id]!.documentJson,
    filesById[id]!.contentRevision,
  );
  @override
  Future<DocumentVersion> writeDocumentVersion(
    int id,
    String body,
    int revision,
  ) async {
    filesById[id] = filesById[id]!.copyWith(
      documentJson: body,
      contentRevision: revision + 1,
    );
    return DocumentVersion(body, revision + 1);
  }

  @override
  Future<List<ObjectEmbed>> loadEmbedsForFile(
    int id, {
    bool notify = true,
  }) async => embedsByFileId[id]!;
  @override
  Future<AppFile> reloadFile(int id, {bool notify = true}) async =>
      filesById[id]!;
  @override
  Future<ObjectEmbed> cloneObjectInDocument(
    AppFile file, {
    required int sourceObjectId,
    required int blockIndex,
  }) async {
    if (fail) throw StateError('source missing');
    sources.add(sourceObjectId);
    final id = sources.length + 1;
    final clone = ObjectEmbed(
      id: id,
      fileId: file.id,
      type: 'info',
      information: Map.of(info.information!),
    );
    embedsByFileId[file.id] = [...embedsByFileId[file.id]!, clone];
    filesById[file.id] = filesById[file.id]!.copyWith(
      documentJson: '${filesById[file.id]!.documentJson}\n\n[INFO id="$id"]',
      contentRevision: file.contentRevision + 1,
    );
    return clone;
  }
}

void main() {
  testWidgets(
    'copy pointer only; repeated paste creates independent nodes; failure keeps document',
    (tester) async {
      final state = MemoryState();
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          if (call.method == 'Clipboard.getData') return {'text': clipboard};
          return null;
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SuperDocumentEditor(
              file: file,
              state: state,
              embeds: const [info],
            ),
          ),
        ),
      );
      await tester.pump();
      Future<void> caretOn(int index) async {
        final surface = tester.widget<SuperEditor>(find.byType(SuperEditor));
        final node = surface.editor.document.getNodeAt(index)!;
        surface.focusNode!.requestFocus();
        await tester.pump();
        surface.editor.execute([
          ChangeSelectionRequest(
            DocumentSelection.collapsed(
              position: DocumentPosition(
                nodeId: node.id,
                nodePosition: node.endPosition,
              ),
            ),
            SelectionChangeType.placeCaret,
            SelectionReason.userInteraction,
          ),
        ]);
        await tester.pump();
      }

      Future<void> action(String name) async {
        final pending = DocumentEditorRegistry.active!.applyTextAction!(name);
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await pending;
      }

      await caretOn(0);
      await action('text:copy');
      expect(clipboard, '[INFO id="1"]');
      for (var i = 0; i < 2; i++) {
        await caretOn(1);
        await action('text:paste');
      }
      expect(state.sources, [1, 1]);
      final doc = tester
          .widget<SuperEditor>(find.byType(SuperEditor))
          .editor
          .document;
      expect(
        [
          for (var i = 0; i < doc.nodeCount; i++)
            if (doc.getNodeAt(i) case ObjectEmbedNode n) n.objectId,
        ],
        [1, 2, 3],
      );
      state.fail = true;
      await caretOn(1);
      await action('text:paste');
      expect(state.sources, [1, 1]);
      expect(find.text(state.strings['objectPasteFailed']), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      state.dispose();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
