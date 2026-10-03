import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/core/app_state.dart';
import 'package:system_app_front_end/areas/files/rich_text/dialog_formatted_field.dart';
import 'package:system_app_front_end/areas/files/rich_text/formatted_text_field.dart';

void main() {
  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    testWidgets('long dialog prompt follows caret and scrolls on $platform', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      final state = AppState();
      final controller = TextEditingController();
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 360,
                  child: DialogFormattedField(
                    controller: controller,
                    strings: state.strings,
                    minLines: 3,
                    maxLines: 8,
                  ),
                ),
              ),
            ),
          ),
        );
        final field = find.byType(FormattedTextField);
        await tester.tap(field);
        await tester.enterText(
          field,
          List.generate(30, (i) => 'Prompt line $i').join('\n'),
        );
        await tester.pumpAndSettle();
        final editable = tester.widget<EditableText>(find.byType(EditableText));
        final scroll = editable.scrollController!;
        expect(scroll.offset, greaterThan(0));
        expect(controller.text, endsWith('Prompt line 29'));
        final endOffset = scroll.offset;
        scroll.jumpTo(0);
        await tester.pump();
        expect(scroll.offset, 0);
        controller.selection = const TextSelection.collapsed(offset: 0);
        await tester.pumpAndSettle();
        await tester.enterText(field, '${controller.text}\nAnother line');
        await tester.pumpAndSettle();
        expect(scroll.offset, greaterThan(endOffset));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        controller.dispose();
        state.dispose();
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
