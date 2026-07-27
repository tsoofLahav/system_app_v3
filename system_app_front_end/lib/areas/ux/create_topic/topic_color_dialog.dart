import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../ui/adaptive_dialog.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_icons.dart';
import '../topic/topic_appearance.dart';

/// Picks a topic's colour, on its own.
///
/// The choice is one of the sixteen the app knows — the topic colour is a
/// wayfinding cue, and a free colour wheel would let the user pick something
/// that reads as nothing once it is washed over a file pane at 10%.
Future<String?> showTopicColorDialog({
  required BuildContext context,
  required AppStrings strings,
  required String selectedHex,
}) {
  return showAppDialog<String>(
    context: context,
    builder: (ctx) => AppAdaptiveDialogShell(
      title: Text(strings['chooseColor']),
      width: 320,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(strings['cancel']),
        ),
      ],
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final hex in TopicAppearance.presetColors)
            _Swatch(
              color: TopicAppearance.colorFromHex(hex),
              selected: hex.toUpperCase() == selectedHex.toUpperCase(),
              onTap: () => Navigator.pop(ctx, hex),
            ),
        ],
      ),
    ),
  );
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? AppColors.text.withValues(alpha: 0.55)
                : Colors.white.withValues(alpha: 0.7),
            width: selected ? 1.4 : 0.8,
          ),
        ),
        child: selected
            ? const Center(
                child: AppIcon(AppIcons.check, size: 15, color: Colors.white),
              )
            : null,
      ),
    );
  }
}
