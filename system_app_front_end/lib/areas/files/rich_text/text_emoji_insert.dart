import '../../../shared/utils/platform_text.dart';
import '../editor/document_editor_controller.dart';
import './block_text_focus.dart';

/// Where an emoji from the insert-bar palette should land.
enum TextEmojiInsertSink { embedField, documentBody }

/// Prefer the surface that currently owns writing. Search in the palette
/// steals focus, so a frozen embed field still wins when nothing else is
/// live — that is how several inserts in a row stay at the same caret.
TextEmojiInsertSink resolveTextEmojiInsertSink({
  required bool embedFieldFocused,
  required bool documentFocused,
  required bool hasFrozenEmbedField,
}) {
  if (embedFieldFocused) return TextEmojiInsertSink.embedField;
  if (documentFocused) return TextEmojiInsertSink.documentBody;
  if (hasFrozenEmbedField) return TextEmojiInsertSink.embedField;
  return TextEmojiInsertSink.documentBody;
}

/// Inserts [emoji] at the writing caret without closing the palette.
void insertEmojiIntoActiveText(String emoji) {
  final sanitized = sanitizePlatformText(emoji);
  if (sanitized.isEmpty) return;

  final fieldFocused =
      BlockTextFocusRegistry.activeFocusNode?.hasFocus == true;
  final documentFocused =
      DocumentEditorRegistry.active?.isFocused?.call() == true &&
      !fieldFocused;
  final sink = resolveTextEmojiInsertSink(
    embedFieldFocused: fieldFocused,
    documentFocused: documentFocused,
    hasFrozenEmbedField: BlockTextFocusRegistry.hasEmojiPickerTarget,
  );

  if (sink == TextEmojiInsertSink.embedField) {
    BlockTextFocusRegistry.insertText(sanitized);
    return;
  }
  DocumentEditorRegistry.active?.applyTextAction?.call('text:emoji:$sanitized');
}
