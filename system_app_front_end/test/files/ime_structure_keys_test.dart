import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/editor/embed_exit_scope.dart';
import 'package:system_app_front_end/areas/files/rich_text/formatted_text_field.dart';
import 'package:system_app_front_end/areas/ui/app_icons.dart';

void main() {
  test('a single IME newline is structure Enter', () {
    expect(imeInsertedSingleNewline('Buy milk', 'Buy milk\n'), isTrue);
    expect(imeInsertedSingleNewline('hel', 'hel\nlo'), isFalse);
    expect(imeInsertedSingleNewline('', '\n'), isTrue);
    expect(
      imeInsertedSingleNewline(imeEmptySentinel, '$imeEmptySentinel\n'),
      isTrue,
    );
    expect(imeInsertedSingleNewline(imeEmptySentinel, '\n'), isTrue);
    expect(imeInsertedSingleNewline('a', 'a\nb'), isFalse);
  });

  test('empty IME delete is the sentinel disappearing', () {
    expect(imeDeletedEmptySentinel(imeEmptySentinel, ''), isTrue);
    expect(imeDeletedEmptySentinel('a', ''), isFalse);
    expect(imeFieldLooksEmpty(imeEmptySentinel), isTrue);
    expect(
      imeVisibleText(
        '$imeEmptySentinel'
        'task',
      ),
      'task',
    );
  });

  test('enter / leave object icons are Lucide, not text', () {
    expect(AppIcons.enterObject, isNotNull);
    expect(AppIcons.leaveObject, isNotNull);
    expect(AppIcons.enterObject, isNot(equals(AppIcons.leaveObject)));
  });

  testWidgets(
    'IME Return on a task-like field calls onEnter and keeps the line',
    (tester) async {
      var enters = 0;
      final controller = TextEditingController(text: 'Buy milk');
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FormattedTextField(
              controller: controller,
              style: const TextStyle(fontSize: 14),
              maxLines: null,
              onEnter: () => enters++,
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'Buy milk\n');
      await tester.pump();

      expect(enters, 1);
      expect(controller.text, 'Buy milk');
    },
  );

  testWidgets('first letter in an empty object field keeps focus', (
    tester,
  ) async {
    final focus = FocusNode();
    final controller = TextEditingController();
    addTearDown(focus.dispose);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FormattedTextField(
            controller: controller,
            focusNode: focus,
            style: const TextStyle(fontSize: 14),
            maxLines: null,
            onEnter: () {},
            onBackspaceAtStart: () async {},
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focus.hasFocus, isTrue);

    await tester.enterText(find.byType(TextField), 'a');
    await tester.pump();

    expect(focus.hasFocus, isTrue);
    expect(controller.text, 'a');
  });

  testWidgets('clearing a task leaves an empty-delete target', (tester) async {
    var backs = 0;
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FormattedTextField(
            controller: controller,
            style: const TextStyle(fontSize: 14),
            maxLines: null,
            onEnter: () {},
            onBackspaceAtStart: () async => backs++,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'a');
    await tester.pump();
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();

    expect(controller.text, imeEmptySentinel);
    expect(controller.selection.baseOffset, 1);
    expect(backs, 0);

    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(backs, 1);
  });

  testWidgets('empty-field IME delete calls onBackspaceAtStart', (
    tester,
  ) async {
    var backs = 0;
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FormattedTextField(
            controller: controller,
            style: const TextStyle(fontSize: 14),
            maxLines: null,
            onBackspaceAtStart: () async => backs++,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(controller.text, imeEmptySentinel);

    await tester.enterText(find.byType(TextField), '');
    await tester.pump();

    expect(backs, 1);
  });

  testWidgets(
    'Shift+Enter inside an object inserts a newline instead of leaving',
    (tester) async {
      var left = 0;
      var enters = 0;
      final controller = TextEditingController(text: 'hello');
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmbedExitScope(
              nodeId: 'embed:1',
              onExit: (_) => left++,
              child: FormattedTextField(
                controller: controller,
                style: const TextStyle(fontSize: 14),
                maxLines: null,
                onEnter: () => enters++,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(left, 0);
      expect(enters, 0);
      expect(controller.text, 'hello\n');
    },
  );

  testWidgets('Enter inside an object without onEnter leaves', (tester) async {
    var left = 0;
    final controller = TextEditingController(text: 'hello');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmbedExitScope(
            nodeId: 'embed:1',
            onExit: (_) => left++,
            child: FormattedTextField(
              controller: controller,
              style: const TextStyle(fontSize: 14),
              maxLines: null,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(left, 1);
    expect(controller.text, 'hello');
  });

  testWidgets('Escape inside an object leaves without changing the text', (
    tester,
  ) async {
    var left = 0;
    final controller = TextEditingController(text: 'hello');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmbedExitScope(
            nodeId: 'embed:1',
            onExit: (_) => left++,
            child: FormattedTextField(
              controller: controller,
              style: const TextStyle(fontSize: 14),
              maxLines: null,
              onEnter: () {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(left, 1);
    expect(controller.text, 'hello');
  });

  testWidgets('⌘Enter inserts a newline instead of calling onEnter', (
    tester,
  ) async {
    var enters = 0;
    final controller = TextEditingController(text: 'hello');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FormattedTextField(
            controller: controller,
            style: const TextStyle(fontSize: 14),
            maxLines: null,
            onEnter: () => enters++,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    expect(enters, 0);
    expect(controller.text, 'hello\n');
  });

  testWidgets('IME newline while ⌘ is down stays a newline', (tester) async {
    var enters = 0;
    final controller = TextEditingController(text: 'Buy milk');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FormattedTextField(
            controller: controller,
            style: const TextStyle(fontSize: 14),
            maxLines: null,
            onEnter: () => enters++,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.enterText(find.byType(TextField), 'Buy milk\n');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    expect(enters, 0);
    expect(controller.text, 'Buy milk\n');
  });

  testWidgets('object fields disable system suggestions', (tester) async {
    final controller = TextEditingController(text: 'Hi');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FormattedTextField(
            controller: controller,
            style: const TextStyle(fontSize: 14),
            maxLines: null,
          ),
        ),
      ),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.autocorrect, isFalse);
    expect(field.enableSuggestions, isFalse);
    expect(field.spellCheckConfiguration?.spellCheckEnabled, isFalse);
  });
}
