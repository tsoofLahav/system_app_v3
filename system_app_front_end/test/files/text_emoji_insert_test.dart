import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/rich_text/block_text_focus.dart';
import 'package:system_app_front_end/areas/files/rich_text/text_emoji_insert.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a focused embed field wins over the document body', () {
    expect(
      resolveTextEmojiInsertSink(
        embedFieldFocused: true,
        documentFocused: true,
        hasFrozenEmbedField: true,
      ),
      TextEmojiInsertSink.embedField,
    );
  });

  test('a focused document body wins when no field is live', () {
    expect(
      resolveTextEmojiInsertSink(
        embedFieldFocused: false,
        documentFocused: true,
        hasFrozenEmbedField: false,
      ),
      TextEmojiInsertSink.documentBody,
    );
  });

  test('clicking the body while the palette is open retargets insert', () {
    expect(
      resolveTextEmojiInsertSink(
        embedFieldFocused: false,
        documentFocused: true,
        hasFrozenEmbedField: true,
      ),
      TextEmojiInsertSink.documentBody,
    );
  });

  test('search stealing focus still inserts into the frozen field', () {
    expect(
      resolveTextEmojiInsertSink(
        embedFieldFocused: false,
        documentFocused: false,
        hasFrozenEmbedField: true,
      ),
      TextEmojiInsertSink.embedField,
    );
  });

  test('body claimed while the palette is open wins after overlay steals focus', () {
    expect(
      resolveTextEmojiInsertSink(
        embedFieldFocused: false,
        documentFocused: false,
        hasFrozenEmbedField: true,
        preferDocument: true,
      ),
      TextEmojiInsertSink.documentBody,
    );
  });

  test('with no field aimed, insert goes to the document body', () {
    expect(
      resolveTextEmojiInsertSink(
        embedFieldFocused: false,
        documentFocused: false,
        hasFrozenEmbedField: false,
      ),
      TextEmojiInsertSink.documentBody,
    );
  });

  test('emoji picker session inserts several emojis at the same caret', () {
    final controller = TextEditingController(text: 'ab');
    controller.selection = const TextSelection.collapsed(offset: 1);
    var changed = 0;
    BlockTextFocusRegistry.register(
      controller: controller,
      changed: () => changed++,
    );
    addTearDown(() {
      BlockTextFocusRegistry.endEmojiPickerSession(restoreFocus: false);
      BlockTextFocusRegistry.unregister(controller);
      controller.dispose();
    });

    BlockTextFocusRegistry.beginEmojiPickerSession();
    BlockTextFocusRegistry.insertText('😀');
    BlockTextFocusRegistry.insertText('🎉');

    expect(controller.text, 'a😀🎉b');
    expect(controller.selection.isCollapsed, isTrue);
    expect(controller.selection.baseOffset, 'a😀🎉'.length);
    expect(changed, 2);
  });

  test('an unfocused object field still receives picker inserts', () {
    final controller = TextEditingController(text: 'ab');
    controller.selection = const TextSelection.collapsed(offset: 1);
    var changed = 0;
    BlockTextFocusRegistry.register(
      controller: controller,
      changed: () => changed++,
    );
    addTearDown(() {
      BlockTextFocusRegistry.endEmojiPickerSession(restoreFocus: false);
      BlockTextFocusRegistry.unregister(controller);
      controller.dispose();
    });

    BlockTextFocusRegistry.unregister(controller);
    BlockTextFocusRegistry.beginEmojiPickerSession(allowUnfocusedRecent: true);
    BlockTextFocusRegistry.insertText('😀');

    expect(controller.text, 'a😀b');
    expect(changed, 1);
  });

  test('moving the caret to another object field retargets picker inserts', () {
    final first = TextEditingController(text: 'ab');
    first.selection = const TextSelection.collapsed(offset: 1);
    final second = TextEditingController(text: 'xy');
    second.selection = const TextSelection.collapsed(offset: 1);
    var firstChanged = 0;
    var secondChanged = 0;
    BlockTextFocusRegistry.register(
      controller: first,
      changed: () => firstChanged++,
    );
    addTearDown(() {
      BlockTextFocusRegistry.endEmojiPickerSession(restoreFocus: false);
      BlockTextFocusRegistry.unregister(first);
      BlockTextFocusRegistry.unregister(second);
      first.dispose();
      second.dispose();
    });

    BlockTextFocusRegistry.beginEmojiPickerSession();
    BlockTextFocusRegistry.register(
      controller: second,
      changed: () => secondChanged++,
    );
    BlockTextFocusRegistry.insertText('😀');

    expect(first.text, 'ab');
    expect(firstChanged, 0);
    expect(second.text, 'x😀y');
    expect(secondChanged, 1);
  });

  test('moving the caret in the same object field updates picker inserts', () {
    final controller = TextEditingController(text: 'hello');
    controller.selection = const TextSelection.collapsed(offset: 1);
    var changed = 0;
    BlockTextFocusRegistry.register(
      controller: controller,
      changed: () => changed++,
    );
    addTearDown(() {
      BlockTextFocusRegistry.endEmojiPickerSession(restoreFocus: false);
      BlockTextFocusRegistry.unregister(controller);
      controller.dispose();
    });

    BlockTextFocusRegistry.beginEmojiPickerSession();
    controller.selection = const TextSelection.collapsed(offset: 4);
    BlockTextFocusRegistry.noteEmojiPickerCaret(controller);
    BlockTextFocusRegistry.insertText('😀');

    expect(controller.text, 'hell😀o');
    expect(changed, 1);
  });

  test('palette opened in the body then a field is aimed inserts into the field', () {
    final controller = TextEditingController(text: 'xy');
    controller.selection = const TextSelection.collapsed(offset: 1);
    var changed = 0;
    addTearDown(() {
      BlockTextFocusRegistry.endEmojiPickerSession(restoreFocus: false);
      BlockTextFocusRegistry.unregister(controller);
      controller.dispose();
    });

    BlockTextFocusRegistry.beginEmojiPickerSession();
    BlockTextFocusRegistry.register(
      controller: controller,
      changed: () => changed++,
    );
    BlockTextFocusRegistry.insertText('😀');

    expect(controller.text, 'x😀y');
    expect(changed, 1);
  });
}
