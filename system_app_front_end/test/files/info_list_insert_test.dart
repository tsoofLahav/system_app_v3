import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:system_app_front_end/core/app_state.dart';
import 'package:system_app_front_end/areas/files/data/app_file.dart';
import 'package:system_app_front_end/areas/files/editor/document_insert_bar.dart';
import 'package:system_app_front_end/areas/files/editor/document_sync.dart';
import 'package:system_app_front_end/areas/files/editor/super_document_editor.dart';
import 'package:system_app_front_end/areas/files/rich_text/formatted_text_field.dart';
import 'package:system_app_front_end/areas/objects/data/object_embed.dart';
import 'package:system_app_front_end/areas/ux/shortcuts/shortcut_dispatcher.dart';
import 'package:system_app_front_end/areas/ux/shortcuts/shortcut_catalog.dart';

const body = '%%system_app_document v4\n\n[INFO id="1"]';
const file = AppFile(id: 77, topicId: 1, name: 'Test', documentJson: body);
const info = ObjectEmbed(
  id: 1,
  fileId: 77,
  type: 'info',
  information: {'title': 'Title', 'body': ''},
);

class MemoryState extends AppState {
  MemoryState() {
    filesById[77] = file;
    embedsByFileId[77] = [info];
  }
  @override
  Future<DocumentVersion> readDocumentVersion(int id) async =>
      const DocumentVersion(body, 1);
  @override
  Future<List<ObjectEmbed>> loadEmbedsForFile(
    int id, {
    bool notify = true,
  }) async => embedsByFileId[id]!;
}

void main() {
  testWidgets(
    'dash/star, list shortcut and both insert buttons stay inside info',
    (tester) async {
      final state = MemoryState();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: SuperDocumentEditor(
                    file: file,
                    state: state,
                    embeds: const [info],
                  ),
                ),
                DocumentInsertBar(state: state),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      final document = tester
          .widget<SuperEditor>(find.byType(SuperEditor))
          .editor
          .document;
      final originalNodeIds = [
        for (var i = 0; i < document.nodeCount; i++) document.getNodeAt(i)!.id,
      ];
      final finder = find.byType(FormattedTextField);
      expect(finder, findsOneWidget);
      await tester.enterText(finder, 'Title\n- ');
      await tester.pump();
      final field = tester.widget<FormattedTextField>(finder);
      expect(field.controller.text, 'Title\n• ');
      await tester.enterText(finder, 'Title\n* ');
      await tester.pump();
      expect(field.controller.text, 'Title\n☐ ');
      await tester.enterText(finder, 'Title\n');
      await dispatchShortcutAction(
        tester.element(finder),
        state,
        ShortcutActionIds.addConnection,
      );
      await tester.pump();
      expect(field.controller.text, 'Title\n• ');
      await tester.enterText(finder, 'Title\n');
      final listButton = find.byWidgetPredicate(
        (w) =>
            w is IconButton &&
            (w.tooltip ?? '').startsWith('${state.strings['list']} ('),
      );
      expect(listButton, findsOneWidget);
      await tester.tap(listButton);
      await tester.pump();
      expect(field.controller.text, 'Title\n• ');
      expect(field.focusNode!.hasFocus, isTrue);
      await tester.enterText(finder, 'Title\n');
      await tester.tap(find.byTooltip(state.strings['addTaskList']));
      await tester.pump();
      expect(field.controller.text, 'Title\n☐ ');
      final editor = tester.widget<SuperEditor>(find.byType(SuperEditor));
      expect(
        [
          for (var i = 0; i < editor.editor.document.nodeCount; i++)
            editor.editor.document.getNodeAt(i)!.id,
        ],
        originalNodeIds,
        reason: 'No top-level list or task object was inserted',
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      state.dispose();
      expect(tester.takeException(), isNull);
    },
  );
}
