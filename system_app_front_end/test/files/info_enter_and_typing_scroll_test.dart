import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/core/app_state.dart';
import 'package:system_app_front_end/areas/objects/data/object_embed.dart';
import 'package:system_app_front_end/areas/files/editor/embeds/object_embed_widgets.dart';
import 'package:system_app_front_end/areas/files/editor/embed_exit_scope.dart';
import 'package:system_app_front_end/areas/files/rich_text/formatted_text_field.dart';

void main() {
  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    testWidgets('info Return stays inside and Escape leaves on $platform', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      final state = AppState();
      var exits = 0;
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EmbedExitScope(
                nodeId: 'info:1',
                onExit: (_) => exits++,
                child: InfoEmbed(
                  embed: const ObjectEmbed(
                    id: 1,
                    fileId: 1,
                    type: 'info',
                    information: {'title': 'Title', 'body': 'body'},
                  ),
                  blockId: 'info:1',
                  state: state,
                  onRefresh: () {},
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byType(FormattedTextField));
        await tester.pump();
        final field = tester.widget<FormattedTextField>(
          find.byType(FormattedTextField),
        );
        field.controller.selection = TextSelection.collapsed(
          offset: field.controller.text.length,
        );
        if (platform == TargetPlatform.iOS) {
          tester.testTextInput.updateEditingValue(
            const TextEditingValue(
              text: 'Title\nbody\n',
              selection: TextSelection.collapsed(offset: 11),
            ),
          );
        } else {
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        }
        await tester.pump();
        expect(field.controller.text, 'Title\nbody\n');
        expect(exits, 0);
        expect(field.focusNode!.hasFocus, isTrue);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pump();
        expect(field.controller.text, 'Title\nbody\n\n');
        expect(exits, 0);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        expect(exits, 1);
        await tester.pump(const Duration(milliseconds: 500));
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        state.dispose();
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  testWidgets('typing scrolls only when the caret crosses the bottom', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'one');
    final scroll = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 120,
            child: SingleChildScrollView(
              controller: scroll,
              child: Column(
                children: [
                  FormattedTextField(
                    controller: controller,
                    maxLines: null,
                    style: const TextStyle(fontSize: 20),
                  ),
                  const SizedBox(height: 500),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(FormattedTextField));
    await tester.enterText(find.byType(FormattedTextField), 'one two');
    await tester.pump();
    expect(scroll.offset, 0);
    await tester.enterText(
      find.byType(FormattedTextField),
      List.filled(12, 'line').join('\n'),
    );
    await tester.pump();
    expect(scroll.offset, greaterThan(0));
    final editable = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    final caret = editable.getLocalRectForCaret(controller.selection.extent);
    expect(editable.localToGlobal(caret.bottomRight).dy, closeTo(120, 2));
    final before = scroll.offset;
    controller.selection = const TextSelection.collapsed(offset: 0);
    await tester.pump();
    expect(scroll.offset, before);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    scroll.dispose();
  });
}
