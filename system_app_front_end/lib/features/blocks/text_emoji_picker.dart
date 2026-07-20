import 'package:flutter/material.dart';

import '../../design_system/adaptive_dialog.dart';
import '../../design_system/glass_surface.dart';
import '../../core/app_state.dart';
import '../create_topic/icon_category_picker.dart';
import 'block_text_focus.dart';

/// Opens the searchable emoji picker and inserts the choice at the text caret.
Future<void> showTextEmojiPicker({
  required BuildContext context,
  required String searchHint,
  String? title,
}) async {
  BlockTextFocusRegistry.beginEmojiPickerSession();
  if (!BlockTextFocusRegistry.hasEmojiPickerTarget) return;

  try {
    await showAppDialog<void>(
      context: context,
      builder: (ctx) => AppGlassDialog(
        width: 360,
        title: Text(title ?? searchHint),
        child: IconCategoryPicker(
          selectedId: '',
          searchHint: searchHint,
          onSelected: (emoji) {
            BlockTextFocusRegistry.insertText(emoji);
            Navigator.pop(ctx);
          },
        ),
      ),
    );
  } finally {
    BlockTextFocusRegistry.endEmojiPickerSession();
  }
}

Future<void> runSuggestEmoji(BuildContext context, AppState state) async {
  final s = state.strings;
  if (!state.canRunAiTool('suggest_emoji')) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s['aiNoContext'])),
    );
    return;
  }

  try {
    final ok = await state.runSuggestEmoji();
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s['aiSuggestEmojiFailed'])),
      );
    }
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString())),
    );
  }
}
