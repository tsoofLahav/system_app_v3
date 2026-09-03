import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../ui/adaptive_dialog.dart';
import '../ui/app_typography.dart';
import './automation.dart';

/// Blocking leftover confirm after a section window ends with unfinished tasks.
Future<void> showLeftoverClearDialogs(BuildContext context, AppState state) async {
  final pending = [...state.pendingClearWindows];
  for (final window in pending) {
    if (!context.mounted) return;
    await showLeftoverClearDialog(context: context, state: state, window: window);
  }
}

Future<void> showLeftoverClearDialog({
  required BuildContext context,
  required AppState state,
  required Automation window,
}) async {
  final payload = window.pendingClear;
  if (payload == null) return;
  final s = state.strings;
  final leftovers = payload['leftovers'];
  final titles = <String>[
    if (leftovers is List)
      for (final item in leftovers)
        if (item is Map && item['title'] != null) '${item['title']}',
  ];
  final viewName = '${payload['view_name'] ?? ''}';
  final sectionName = '${payload['section_name'] ?? ''}';

  final approved = await showAppDialog<bool>(
    context: context,
    useBottomSheet: false,
    isDismissible: false,
    builder: (ctx) => AppAdaptiveDialogShell(
      title: Text(s['leftoverClearTitle']),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(s['leftoverClearApprove']),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.leftoverClearMessage(viewName, sectionName),
            style: AppTypography.metaStyle,
          ),
          if (titles.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final title in titles)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• $title', style: AppTypography.taskRowStyle),
              ),
          ],
        ],
      ),
    ),
  );
  if (approved != true) return;
  await state.approveTaskResetAcknowledgement();
}
