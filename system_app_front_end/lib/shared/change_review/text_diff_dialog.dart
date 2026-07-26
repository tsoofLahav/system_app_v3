import 'package:flutter/material.dart';

import '../../design_system/app_colors.dart';
import '../../design_system/glass_surface.dart';
import 'change_review_dialog.dart';

class TextDiffDialog extends StatelessWidget {
  const TextDiffDialog({
    super.key,
    required this.title,
    required this.diffHunks,
    required this.onApply,
    required this.onDismiss,
    this.applyLabel = 'Apply',
    this.dismissLabel = 'Dismiss',
  });

  final String title;
  final String diffHunks;
  final VoidCallback onApply;
  final VoidCallback onDismiss;
  final String applyLabel;
  final String dismissLabel;

  static Future<bool?> show(
    BuildContext context, {
    required String title,
    required String diffHunks,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => TextDiffDialog(
        title: title,
        diffHunks: diffHunks,
        onApply: () => Navigator.pop(ctx, true),
        onDismiss: () => Navigator.pop(ctx, false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeReviewDialogShell(
      title: title,
      child: SingleChildScrollView(
        child: SelectableText(
          diffHunks.isEmpty ? '(no changes)' : diffHunks,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            height: 1.45,
            color: AppColors.text,
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: onDismiss, child: Text(dismissLabel)),
        FilledButton(onPressed: onApply, child: Text(applyLabel)),
      ],
    );
  }
}
