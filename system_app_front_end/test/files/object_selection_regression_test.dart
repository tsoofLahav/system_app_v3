import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:system_app_front_end/areas/files/rich_text/rtl/editable_selection_controls.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/rich_text/formatted_text_field.dart';
import 'package:system_app_front_end/areas/files/rich_text/span_text_editing_controller.dart';

void main() {
  const fontPath = String.fromEnvironment(
    'RTL_TEST_FONT',
    defaultValue: '/System/Library/Fonts/Supplemental/Arial.ttf',
  );
  final hasFont = File(fontPath).existsSync();
  setUpAll(() async {
    if (!hasFont) return;
    final loader = FontLoader('HebrewTest');
    loader.addFont(
      Future.value(ByteData.sublistView(await File(fontPath).readAsBytes())),
    );
    await loader.load();
  });
  for (final linked in [false, true]) {
    testWidgets('mouse drag across Hebrew and numbers linked=$linked', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

      final c = SpanTextEditingController(
        text: 'שורה באובייקט 4444 עם מספרים באמצע',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 500,
                child: FormattedTextField(
                  controller: c,
                  style: const TextStyle(
                    fontFamily: 'HebrewTest',
                    fontSize: 22,
                  ),
                  descriptionRanges: linked
                      ? [
                          const DescriptionTextRange(
                            start: 0,
                            end: 4,
                            link: {'id': 1},
                          ),
                        ]
                      : const [],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final e = tester
          .state<EditableTextState>(find.byType(EditableText))
          .renderEditable;
      final boxes = e.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: c.text.length),
      );
      final start = e.localToGlobal(
        Offset(
          boxes.map((b) => b.right).reduce((a, b) => a > b ? a : b) - 1,
          boxes.first.toRect().center.dy,
        ),
      );
      final end = e.localToGlobal(
        Offset(
          boxes.map((b) => b.left).reduce((a, b) => a < b ? a : b) + 1,
          boxes.first.toRect().center.dy,
        ),
      );
      final g = await tester.startGesture(start, kind: PointerDeviceKind.mouse);
      await g.moveTo(Offset.lerp(start, end, .5)!);
      await tester.pump();
      await g.moveTo(end);
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue,
      );
      expect(c.selection.start, 0);
      expect(c.selection.end, c.text.length);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
      debugDefaultTargetPlatformOverride = null;
    }, skip: !hasFont);
  }
  testWidgets(
    'iOS mixed-number word tap, double tap and logical handle anchors',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final c = SpanTextEditingController(
        text: 'שורה באובייקט 4444 עם מספרים באמצע',
      );
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 360,
                  child: FormattedTextField(
                    controller: c,
                    style: const TextStyle(
                      fontFamily: 'HebrewTest',
                      fontSize: 22,
                    ),
                    descriptionRanges: const [
                      DescriptionTextRange(start: 0, end: 4, link: {'id': 1}),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final state = tester.state<EditableTextState>(
          find.byType(EditableText),
        );
        final e = state.renderEditable;
        final start = c.text.indexOf('4444');
        final box = e
            .getBoxesForSelection(
              TextSelection(baseOffset: start, extentOffset: start + 4),
            )
            .single;
        final point = e.localToGlobal(
          Offset(box.left + box.toRect().width * .4, box.toRect().center.dy),
        );
        await tester.tapAt(point);
        await tester.pump();
        expect(
          [start, start + 4],
          contains(c.selection.extentOffset),
          reason: 'A phone tap must not land inside a number/word',
        );
        await tester.pump(const Duration(milliseconds: 60));
        await tester.tapAt(point);
        await tester.pumpAndSettle();
        expect(c.selection.start, start);
        expect(c.selection.end, start + 4);
        c.selection = TextSelection(
          baseOffset: start,
          extentOffset: c.text.length,
        );
        await tester.pump();
        final native = e.getEndpointsForSelection(c.selection);
        final logical = editableLogicalSelectionEndpoints(
          e,
          c.text,
          c.selection,
        )!;
        final controls = ObjectCupertinoSelectionControls(
          () => e,
          () => c.text,
        );
        final standard = CupertinoTextSelectionControls();
        for (final pair in [
          (0, TextSelectionHandleType.right),
          (1, TextSelectionHandleType.left),
        ]) {
          final anchor = controls.getHandleAnchor(
            pair.$2,
            e.preferredLineHeight,
          );
          final base = standard.getHandleAnchor(pair.$2, e.preferredLineHeight);
          final stem = native[pair.$1].point - (anchor - base);
          expect((stem - logical[pair.$1]).distance, lessThan(.01));
        }
        expect(state.widget.focusNode.hasFocus, isTrue);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
        debugDefaultTargetPlatformOverride = null;
      }
    },
    skip: !hasFont,
  );
}
