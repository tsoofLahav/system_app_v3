import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:follow_the_leader/follow_the_leader.dart';

import '../../../core/l10n/app_strings.dart';

/// Cut / Copy / Paste plus phone-only **More** and optional **Info**.
List<ContextMenuButtonItem> phoneMarkButtonItems({
  required AppStrings strings,
  required VoidCallback onCut,
  required VoidCallback onCopy,
  required VoidCallback onPaste,
  required VoidCallback onMore,
  VoidCallback? onInfo,
}) {
  return [
    ContextMenuButtonItem(
      type: ContextMenuButtonType.cut,
      label: strings['cut'],
      onPressed: onCut,
    ),
    ContextMenuButtonItem(
      type: ContextMenuButtonType.copy,
      label: strings['copy'],
      onPressed: onCopy,
    ),
    ContextMenuButtonItem(
      type: ContextMenuButtonType.paste,
      label: strings['paste'],
      onPressed: onPaste,
    ),
    if (onInfo != null)
      ContextMenuButtonItem(
        type: ContextMenuButtonType.custom,
        label: strings['info'],
        onPressed: onInfo,
      ),
    ContextMenuButtonItem(
      type: ContextMenuButtonType.custom,
      label: strings['more'],
      onPressed: onMore,
    ),
  ];
}

List<IOSSystemContextMenuItem> phoneMarkSystemItems({
  required AppStrings strings,
  required VoidCallback onCut,
  required VoidCallback onCopy,
  required VoidCallback onPaste,
  required VoidCallback onMore,
  VoidCallback? onInfo,
}) {
  return [
    IOSSystemContextMenuItemCustom(title: strings['cut'], onPressed: onCut),
    IOSSystemContextMenuItemCustom(title: strings['copy'], onPressed: onCopy),
    IOSSystemContextMenuItemCustom(title: strings['paste'], onPressed: onPaste),
    if (onInfo != null)
      IOSSystemContextMenuItemCustom(title: strings['info'], onPressed: onInfo),
    IOSSystemContextMenuItemCustom(title: strings['more'], onPressed: onMore),
  ];
}

/// iOS Cut / Copy / Paste buttons — same widgets the object-field bar uses.
List<Widget> phoneMarkToolbarButtons({
  required AppStrings strings,
  required VoidCallback onCut,
  required VoidCallback onCopy,
  required VoidCallback onPaste,
  required VoidCallback onMore,
  VoidCallback? onInfo,
}) {
  return [
    for (final item in phoneMarkButtonItems(
      strings: strings,
      onCut: onCut,
      onCopy: onCopy,
      onPaste: onPaste,
      onMore: onMore,
      onInfo: onInfo,
    ))
      CupertinoTextSelectionToolbarButton.buttonItem(buttonItem: item),
  ];
}

/// Super Editor iOS mark toolbar. Super Editor already places this widget
/// with a [Follower] on [focalPoint] — do not self-position with global
/// anchors ([AdaptiveTextSelectionToolbar] does, and the bar vanishes).
///
/// Chrome matches the object-field bar ([CupertinoTextSelectionToolbarButton]
/// on a light iOS pill). The Follower owns position; this is paint only.
class PhoneIosMarkToolbar extends StatelessWidget {
  const PhoneIosMarkToolbar({
    super.key,
    required this.focalPoint,
    required this.strings,
    required this.onCut,
    required this.onCopy,
    required this.onPaste,
    required this.onMore,
    this.onInfo,
    this.onSystemHide,
  });

  final LeaderLink focalPoint;
  final AppStrings strings;
  final VoidCallback onCut;
  final VoidCallback onCopy;
  final VoidCallback onPaste;
  final VoidCallback onMore;
  final VoidCallback? onInfo;
  final VoidCallback? onSystemHide;

  @override
  Widget build(BuildContext context) {
    final buttons = phoneMarkToolbarButtons(
      strings: strings,
      onCut: onCut,
      onCopy: onCopy,
      onPaste: onPaste,
      onMore: onMore,
      onInfo: onInfo,
    );
    final divider = CupertinoColors.separator.resolveFrom(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey6.resolveFrom(context),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < buttons.length; i++) ...[
              if (i > 0)
                SizedBox(
                  width: 1,
                  height: 16,
                  child: ColoredBox(color: divider),
                ),
              buttons[i],
            ],
          ],
        ),
      ),
    );
  }
}
