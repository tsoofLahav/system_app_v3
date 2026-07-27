import 'package:flutter/material.dart';

import './adaptive_dialog.dart';
import './app_colors.dart';
import './app_typography.dart';

/// Asks one question and takes one answer.
///
/// Every confirmation in the app goes through here, so "are you sure" always
/// looks the same wherever it is raised. A destructive answer is amber-brown
/// text, never a red button — the app does not shout at the user.
Future<bool> showAppConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
  required String cancelLabel,
  bool destructive = false,
}) async {
  final answer = await showAppDialog<bool>(
    context: context,
    builder: (ctx) => AppAdaptiveDialogShell(
      title: Text(title),
      width: 360,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelLabel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: destructive
              ? TextButton.styleFrom(foregroundColor: AppColors.destructive)
              : null,
          child: Text(confirmLabel),
        ),
      ],
      child: Text(
        message,
        style: AppTypography.noteBodyStyle.copyWith(
          fontSize: 12,
          color: AppColors.text.withValues(alpha: 0.9),
        ),
      ),
    ),
  );
  return answer ?? false;
}
