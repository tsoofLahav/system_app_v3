import 'package:flutter/material.dart';

import '../../../design_system/adaptive_dialog.dart';
import '../../../design_system/glass_surface.dart';
import 'block_text_focus.dart';

Future<String?> showTextEmojiPicker({
  required BuildContext context,
  String title = 'Insert emoji…',
  String searchHint = 'Search emoji',
}) async {
  return showAdaptiveDialog<String>(
    context: context,
    builder: (ctx) => _EmojiPickerDialog(title: title, searchHint: searchHint),
  );
}

class _EmojiPickerDialog extends StatefulWidget {
  const _EmojiPickerDialog({required this.title, required this.searchHint});

  final String title;
  final String searchHint;

  @override
  State<_EmojiPickerDialog> createState() => _EmojiPickerDialogState();
}

class _EmojiPickerDialogState extends State<_EmojiPickerDialog> {
  static const _emojis = ['✅', '⭐', '📝', '🎯', '💡', '📌', '🔥', '❤️', '👍', '🚀'];

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final emoji in _emojis)
                  InkWell(
                    onTap: () => Navigator.pop(context, emoji),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(emoji, style: const TextStyle(fontSize: 24)),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
