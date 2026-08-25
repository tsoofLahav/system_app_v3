import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../ui/adaptive_dialog.dart';
import '../../ui/dialog_metrics.dart';
import './icon_category_picker.dart';

/// Picks a topic's emoji, on its own.
///
/// The picker is tall and busy, which is exactly why it does not belong inside
/// the topic dialog: a dialog should show the few decisions it is asking for,
/// not a grid of a thousand.
Future<String?> showTopicEmojiDialog({
  required BuildContext context,
  required AppStrings strings,
  required String selected,
}) {
  return showAppDialog<String>(
    context: context,
    builder: (ctx) => AppAdaptiveDialogShell(
      title: Text(strings['chooseEmoji']),
      width: AppDialogMetrics.wideWidth,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(strings['cancel']),
        ),
      ],
      child: IconCategoryPicker(
        selectedId: selected,
        searchHint: strings['searchEmoji'],
        keyboardHint: strings['emojiPickerKeyboardHint'],
        onSelected: (emoji) => Navigator.pop(ctx, emoji),
      ),
    ),
  );
}
