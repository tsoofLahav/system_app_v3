import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_state.dart';
import '../../../core/l10n/app_strings.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_icons.dart';
import '../../ui/adaptive_dialog.dart';
import './info_description_bubble.dart';

/// Phone: the description hover bubble as a dismissible dialog (outside tap or ×).
Future<void> showInfoDescriptionModal({
  required BuildContext context,
  required AppStrings strings,
  required String title,
  required String body,
  int? infoObjectId,
}) {
  AppState? state;
  try {
    state = context.read<AppState>();
  } catch (_) {}
  return showAppDialog<void>(
    context: context,
    builder: (ctx) {
      return Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 48),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            InfoDescriptionBubble(
              title: title,
              body: body,
              maxHeight: 360,
              onToggleInner: infoObjectId == null || state == null
                  ? null
                  : (currentBody, markOffset) => state!.toggleInnerTaskOnInfo(
                        infoObjectId: infoObjectId,
                        body: currentBody,
                        markOffset: markOffset,
                      ),
            ),
            PositionedDirectional(
              top: 4,
              end: 4,
              child: IconButton(
                tooltip: strings['close'],
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () => Navigator.of(ctx).pop(),
                icon: AppIcon(
                  AppIcons.close,
                  size: 16,
                  color: AppColors.text.withValues(alpha: 0.72),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
