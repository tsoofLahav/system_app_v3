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
}
