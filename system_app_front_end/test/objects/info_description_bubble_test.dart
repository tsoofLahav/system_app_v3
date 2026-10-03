import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import 'package:system_app_front_end/core/app_state.dart';
import 'package:system_app_front_end/areas/files/rich_text/formatted_text_field.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/objects/data/inner_task_mark.dart';
import 'package:system_app_front_end/areas/objects/data/inner_tasks.dart';
import 'package:system_app_front_end/areas/objects/links/info_description_bubble.dart';

void main() {
  testWidgets(
    'pointer can enter the task preview and toggle without editing text',
    (tester) async {
      final state = _PreviewState();
      final controller = TextEditingController(text: 'Task');
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(40),
                child: FormattedTextField(
                  controller: controller,
                  style: const TextStyle(fontSize: 16),
                  descriptionRanges: const [
                    DescriptionTextRange(
                      start: 0,
                      end: 4,
                      link: {
                        'peer': {'id': 10, 'title': 'Info', 'body': '☐ first'},
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(
        tester.getTopLeft(find.byType(EditableText)) + const Offset(10, 10),
      );
      await tester.pump();
      expect(find.byType(InfoDescriptionBubble), findsOneWidget);
      await mouse.moveTo(tester.getCenter(find.byType(InnerTaskMark)));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(InfoDescriptionBubble), findsOneWidget);
      await tester.tap(find.byType(InnerTaskMark));
      await tester.pump();
      expect(state.toggles, 1);
      expect(
        tester.widget<InnerTaskMark>(find.byType(InnerTaskMark)).done,
        isTrue,
      );
      expect(controller.text, 'Task');
      expect(
        find.descendant(
          of: find.byType(InfoDescriptionBubble),
          matching: find.byType(EditableText),
        ),
        findsNothing,
      );
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      state.dispose();
    },
  );

  testWidgets('preview stays read-only and rapid clicks paint before saving', (
    tester,
  ) async {
    final saves = <Completer<String?>>[];
    final bodies = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InfoDescriptionBubble(
            title: 'Title',
            body: 'prose\n☐ first\n• ordinary',
            onToggleInner: (body, offset) {
              bodies.add(body);
              final save = Completer<String?>();
              saves.add(save);
              return save.future;
            },
          ),
        ),
      ),
    );
    expect(find.byType(EditableText), findsNothing);
    await tester.tap(find.byType(InnerTaskMark));
    await tester.pump();
    expect(
      tester.widget<InnerTaskMark>(find.byType(InnerTaskMark)).done,
      isTrue,
    );
    await tester.tap(find.byType(InnerTaskMark));
    await tester.pump();
    expect(
      tester.widget<InnerTaskMark>(find.byType(InnerTaskMark)).done,
      isFalse,
    );
    expect(saves.length, 1);
    saves.first.complete(
      toggleInnerTaskAt(bodies.first, bodies.first.indexOf('☐')),
    );
    await tester.pump();
    expect(saves.length, 2);
    expect(
      tester.widget<InnerTaskMark>(find.byType(InnerTaskMark)).done,
      isFalse,
    );
    saves.last.complete('prose\n☐ first\n• ordinary');
    await tester.pump();
    expect(
      tester.widget<InnerTaskMark>(find.byType(InnerTaskMark)).done,
      isFalse,
    );
    expect(find.text('Title'), findsOneWidget);
    expect(find.text('• ordinary'), findsOneWidget);
  });

  testWidgets('failed save rolls back and shows error without throwing', (
    tester,
  ) async {
    final save = Completer<String?>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InfoDescriptionBubble(
            title: 'Title',
            body: '☐ first',
            toggleErrorText: 'Save failed',
            onToggleInner: (_, _) => save.future,
          ),
        ),
      ),
    );
    await tester.tap(find.byType(InnerTaskMark));
    await tester.pump();
    expect(
      tester.widget<InnerTaskMark>(find.byType(InnerTaskMark)).done,
      isTrue,
    );
    save.completeError(StateError('offline'));
    await tester.pump();
    expect(
      tester.widget<InnerTaskMark>(find.byType(InnerTaskMark)).done,
      isFalse,
    );
    expect(find.text('Save failed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _PreviewState extends AppState {
  int toggles = 0;
  @override
  Future<String?> toggleInnerTaskOnInfo({
    required int infoObjectId,
    required String body,
    required int markOffset,
  }) async {
    toggles++;
    return toggleInnerTaskAt(body, markOffset);
  }
}
