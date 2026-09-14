import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_text_layout/super_text_layout.dart';
import 'package:super_editor/super_editor.dart';
import 'package:system_app_front_end/areas/files/rich_text/formatted_text_field.dart';
import 'package:system_app_front_end/areas/files/rich_text/rtl/rtl.dart';

void main() {
  const fontPath = String.fromEnvironment('RTL_TEST_FONT');
  setUpAll(() async {
    if (fontPath.isEmpty) return;
    final loader = FontLoader('RtlProbe');
    loader.addFont(
      Future.value(ByteData.sublistView(await File(fontPath).readAsBytes())),
    );
    await loader.load();
  });
  testWidgets(
    'padding resolves every rendered Hebrew line at its center',
    (tester) async {
      const text = 'שלום 123\nשורה ABC\nסוף 456';
      final controller = TextEditingController(text: text);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Directionality(
              textDirection: TextDirection.rtl,
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: SizedBox(
                  width: 400,
                  child: FormattedTextField(
                    controller: controller,
                    maxLines: null,
                    style: const TextStyle(
                      fontFamily: 'RtlProbe',
                      fontSize: 20,
                      height: 1.55,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final editable = tester
          .state<EditableTextState>(find.byType(EditableText))
          .renderEditable;
      var start = 0;
      for (final line in text.split('\n')) {
        final end = start + line.length;
        final boxes = editable.getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: end),
        );
        final y = (boxes.first.top + boxes.first.bottom) / 2;
        final selection = embedCaretForTap(
          editable: editable,
          globalPosition: editable.localToGlobal(Offset(2, y)),
          textLength: text.length,
        );
        expect(
          selection.extentOffset,
          end,
          reason: 'padding at line $start..$end',
        );
        for (final dy in [-8.0, -4.0, 0.0, 4.0, 8.0]) {
          final hit = embedCaretForTap(
            editable: editable,
            globalPosition: editable.localToGlobal(Offset(2, y + dy)),
            textLength: text.length,
          );
          expect(
            hit.extentOffset,
            end,
            reason: 'line $start..$end at center + $dy',
          );
        }
        final left = boxes.map((b) => b.left).reduce((a, b) => a < b ? a : b);
        final near = embedCaretForTap(
          editable: editable,
          globalPosition: editable.localToGlobal(Offset(left - 2, y)),
          textLength: text.length,
        );
        expect(
          near.extentOffset,
          end,
          reason: 'just outside glyph edge on $start..$end',
        );
        await tester.tapAt(
          editable.localToGlobal(Offset(left - 2, y)),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        expect(
          controller.selection.extentOffset,
          end,
          reason: 'real tap at line $start..$end',
        );
        await tester.pump(const Duration(milliseconds: 600));
        start = end + 1;
      }
    },
    skip: fontPath.isEmpty,
  );
  testWidgets('SE layout padding reaches the logical end of Hebrew', (
    tester,
  ) async {
    const text = 'שלום 123\nשורה ABC\nסוף 456';
    final key = GlobalKey<SuperTextState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: SuperText(
              key: key,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.start,
              richText: const TextSpan(
                text: text,
                style: TextStyle(
                  fontFamily: 'RtlProbe',
                  fontSize: 20,
                  height: 1.55,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final layout = key.currentState!.textLayout;
    var start = 0;
    for (final line in text.split('\n')) {
      final end = start + line.length;
      final boxes = layout.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: end),
      );
      final y = (boxes.first.top + boxes.first.bottom) / 2;
      final offset = bidiAwareOffsetFromBoxes(
        boxes: boxes
            .map((b) => Rect.fromLTRB(b.left, b.top, b.right, b.bottom))
            .toList(),
        local: Offset(2, y),
        textLength: text.length,
        paddingGoesToLineEnd: true,
        offsetAt: (point) => layout.getPositionNearestToOffset(point).offset,
        logicalLineEndAt: (point) =>
            logicalLineEndForTextLayout(layout, text, point),
      );
      expect(offset, end, reason: 'SE line $start..$end');
      start = end + 1;
    }
  }, skip: fontPath.isEmpty);
  for (final asList in [false, true]) {
    for (final suffix in ['123', 'ABC']) {
      testWidgets(
        'SE padding reaches trailing $suffix (list: $asList)',
        (tester) async {
          final text = 'שלום $suffix\nשורה 456';
          final TextNode node = asList
              ? ListItemNode.unordered(
                  id: 'p',
                  text: AttributedText(text),
                  indent: 1,
                )
              : ParagraphNode(id: 'p', text: AttributedText(text));
          final doc = MutableDocument(nodes: [node]);
          final composer = MutableDocumentComposer();
          final layoutKey = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: 400,
                  child: SuperEditor(
                    editor: createDefaultDocumentEditor(
                      document: doc,
                      composer: composer,
                    ),
                    documentLayoutKey: layoutKey,
                    stylesheet: Stylesheet(
                      documentPadding: EdgeInsets.zero,
                      inlineTextStyler: defaultInlineTextStyler,
                      rules: [
                        StyleRule(
                          BlockSelector.all,
                          (doc, node) => {
                            Styles.textAlign: TextAlign.start,
                            Styles.textStyle: const TextStyle(
                              fontFamily: 'RtlProbe',
                              fontSize: 20,
                              height: 1.55,
                            ),
                          },
                        ),
                      ],
                    ),
                    componentBuilders: [
                      ...ambientAwareTextBuilders(TextDirection.rtl),
                      ...defaultComponentBuilders,
                    ],
                    contentTapDelegateFactories: [bidiCaretTapHandler()],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final layout = layoutKey.currentState as DocumentLayout;
          final component =
              (layout.getComponentByNodeId('p') as ProxyTextComposable)
                      .childTextComposable
                  as TextComponentState;
          final box = component.context.findRenderObject() as RenderBox;
          for (final end in [text.indexOf('\n'), text.length]) {
            final digit = component.textLayout
                .getBoxesForSelection(
                  TextSelection(baseOffset: end - 1, extentOffset: end),
                )
                .single;
            await tester.tapAt(
              box.localToGlobal(Offset(2, (digit.top + digit.bottom) / 2)),
              kind: PointerDeviceKind.mouse,
            );
            await tester.pump();
            final selection = composer.selection!;
            expect(
              (selection.extent.nodePosition as TextNodePosition).offset,
              end,
            );
            final caret = component.getRectForPosition(
              selection.extent.nodePosition,
            );
            expect(
              caret.left,
              closeTo(digit.right, 1),
              reason: 'caret at trailing LTR run edge',
            );
            await tester.pump(const Duration(milliseconds: 600));
          }
          await tester.pumpWidget(const SizedBox.shrink());
          composer.dispose();
        },
        skip: fontPath.isEmpty,
      );
    }
  }
  testWidgets(
    'SE glyph clicks stay native at wrapped Hebrew line ends',
    (tester) async {
      const text = 'תכנית כללית תכנית כללית תכנית כללית';
      final doc = MutableDocument(
        nodes: [ParagraphNode(id: 'p', text: AttributedText(text))],
      );
      final composer = MutableDocumentComposer();
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 130,
              child: SuperEditor(
                editor: createDefaultDocumentEditor(
                  document: doc,
                  composer: composer,
                ),
                documentLayoutKey: key,
                stylesheet: Stylesheet(
                  documentPadding: EdgeInsets.zero,
                  inlineTextStyler: defaultInlineTextStyler,
                  rules: [
                    StyleRule(
                      BlockSelector.all,
                      (_, __) => {
                        Styles.textAlign: TextAlign.start,
                        Styles.textStyle: const TextStyle(
                          fontFamily: 'RtlProbe',
                          fontSize: 20,
                          height: 1.55,
                        ),
                      },
                    ),
                  ],
                ),
                componentBuilders: [
                  ...ambientAwareTextBuilders(TextDirection.rtl),
                  ...defaultComponentBuilders,
                ],
                contentTapDelegateFactories: [bidiCaretTapHandler()],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final layout = key.currentState as DocumentLayout;
      final component =
          (layout.getComponentByNodeId('p') as ProxyTextComposable)
                  .childTextComposable
              as TextComponentState;
      final box = component.context.findRenderObject() as RenderBox;
      var upstreamHits = 0;
      for (var index = 0; index < text.length; index++) {
        if (text[index] == ' ') continue;
        final glyph = component.textLayout
            .getBoxesForSelection(
              TextSelection(baseOffset: index, extentOffset: index + 1),
            )
            .single;
        final local = Offset(glyph.left + 0.1, (glyph.top + glyph.bottom) / 2);
        final expected = component.textLayout.getPositionNearestToOffset(local);
        if (expected.affinity != TextAffinity.upstream) continue;
        upstreamHits++;
        expect(
          paddingDocumentPosition(
            document: doc,
            layout: layout,
            layoutOffset: layout.getDocumentOffsetFromAncestorOffset(
              box.localToGlobal(local),
            ),
            globalOffset: box.localToGlobal(local),
          ),
          isNull,
          reason: 'glyph hit must fall through to native SE',
        );
        await tester.tapAt(
          box.localToGlobal(local),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        final actual =
            composer.selection!.extent.nodePosition as TextNodePosition;
        expect(actual.offset, expected.offset);
        expect(actual.affinity, expected.affinity);
        expect(
          component.getRectForPosition(actual),
          component.getRectForPosition(expected),
        );
        await tester.pump(const Duration(milliseconds: 600));
      }
      expect(upstreamHits, greaterThan(0));
      await tester.pumpWidget(const SizedBox.shrink());
      composer.dispose();
    },
    skip: fontPath.isEmpty,
  );
  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    testWidgets('Hebrew caret sits on glyph boundaries on $platform', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      final controller = TextEditingController(text: 'אבגדהוזח');
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 400,
                child: FormattedTextField(
                  controller: controller,
                  maxLines: null,
                  style: const TextStyle(
                    fontFamily: 'RtlProbe',
                    fontSize: 20,
                    height: 1.55,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final editable = tester
            .state<EditableTextState>(find.byType(EditableText))
            .renderEditable;
        for (var offset = 0; offset < controller.text.length; offset++) {
          final box = editable
              .getBoxesForSelection(
                TextSelection(baseOffset: offset, extentOffset: offset + 1),
              )
              .single;
          final caret = editable.getLocalRectForCaret(
            TextPosition(offset: offset),
          );
          expect(
            (caret.center.dx - box.right).abs(),
            lessThanOrEqualTo(3),
            reason: 'caret before Hebrew character $offset',
          );
          expect(caret.center.dy, inInclusiveRange(box.top, box.bottom));
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        debugDefaultTargetPlatformOverride = null;
      }
    }, skip: fontPath.isEmpty);
  }
}
