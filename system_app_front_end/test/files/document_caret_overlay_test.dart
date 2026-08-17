import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:system_app_front_end/areas/files/editor/super_document_editor.dart';

/// A pane with a caret parked in the middle of its only paragraph.
Future<void> pumpPane(WidgetTester tester, {required bool withCaret}) async {
  final document = MutableDocument(nodes: [
    ParagraphNode(id: '1', text: AttributedText('Hello world')),
  ]);
  final composer = MutableDocumentComposer(
    initialSelection: const DocumentSelection.collapsed(
      position: DocumentPosition(
        nodeId: '1',
        nodePosition: TextNodePosition(offset: 3),
      ),
    ),
  );

  await tester.pumpWidget(
    MaterialApp(
      home: TickerMode(
        enabled: false,
        child: Scaffold(
          body: SizedBox(
            width: 400,
            height: 200,
            child: SuperEditor(
              editor: createDefaultDocumentEditor(
                document: document,
                composer: composer,
              ),
              inputRole: 'test',
              documentOverlayBuilders:
                  documentOverlayBuilders(withCaret: withCaret),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  // The desktop caret and the mobile handle layers are different overlays, and
  // each of them draws a cursor on its own platform.
  for (final platform in [TargetPlatform.macOS, TargetPlatform.android]) {
    group('one cursor across open files (${platform.name})', () {
      testWidgets('the pane that owns the cursor draws a caret',
          (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        await pumpPane(tester, withCaret: true);

        expect(find.byKey(DocumentKeys.caret), findsOneWidget);

        // The binding checks for a leaked override the moment the body ends.
        debugDefaultTargetPlatformOverride = null;
      });

      testWidgets('another open file draws none, selection and all',
          (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        await pumpPane(tester, withCaret: false);

        // Not merely invisible: the caret paints its own alpha over the colour,
        // so styling it away leaves a solid black cursor behind.
        expect(find.byKey(DocumentKeys.caret), findsNothing);

        debugDefaultTargetPlatformOverride = null;
      });
    });
  }

  test('the layer list keeps its length either way', () {
    // ContentLayers matches overlays by index and never deactivates one past
    // the end of a shorter list — a dropped layer would keep painting.
    expect(
      documentOverlayBuilders(withCaret: false).length,
      documentOverlayBuilders(withCaret: true).length,
    );
  });
}
