import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../design_system/app_typography.dart';
import '../../design_system/glass_surface.dart';

Future<bool> showAutomationAbandonChangesDialog({
  required BuildContext context,
  required AppState state,
}) async {
  final s = state.strings;
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AppGlassDialog(
      title: Text(s['automationAbandonTitle']),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(s['cancel']),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(s['automationAbandonConfirm']),
        ),
      ],
      child: Text(
        s['automationAbandonBody'],
        style: AppTypography.noteBodyStyle,
        textAlign: TextAlign.start,
      ),
    ),
  );
  return result ?? false;
}
